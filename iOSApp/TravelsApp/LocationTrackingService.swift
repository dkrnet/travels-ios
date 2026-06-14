// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.

// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.
import CoreLocation
import Foundation
import UIKit

#if canImport(TravelsCore)
import TravelsCore
#endif

@MainActor
final class LocationTrackingService: NSObject, @preconcurrency CLLocationManagerDelegate {
    private enum ManagerMode {
        case stopped
        case idleDetection
        case activeTracking
    }

    private let locationManager = CLLocationManager()
    private weak var store: TravelsStore?
    private var settings = AppSettings()
    private var trackingStateMachine = LocationTrackingStateMachine()
    private var latestAcceptedEvent: LocationEvent?
    private var isConfigured = false
    private var pendingAlwaysAuthorization = false
    private var didScheduleAlwaysAuthorizationUpgrade = false
    private var isPausing = false
    private var pendingManualCapture = false
    private var pendingForcedStoppedCapture = false
    private var pendingLocation: CLLocation?
    private nonisolated(unsafe) var locationProcessingTask: Task<Void, Never>?
    private nonisolated(unsafe) var hybridTrackingWatchdogTask: Task<Void, Never>?
    private nonisolated(unsafe) var finalPreciseExitTask: Task<Void, Never>?
    private nonisolated(unsafe) var powerStateReevaluationTask: Task<Void, Never>?
    private var hybridTrackingWatchdog = HybridTrackingWatchdog()
    private var powerState = LocationTrackingPowerState()
    private var managerMode: ManagerMode = .stopped
    private var isCompletingHybridPreciseExit = false
    private var ignoreAutomaticLocationUpdatesUntil: Date?

    var onStatusMessage: ((String) -> Void)?
    var onTraceMessage: ((String) -> Void)?
    var onTrackedEvent: (() -> Void)?
    var onManualTrackedEvent: ((Int64, Date) -> Void)?
    var onAuthorizationStateChanged: ((String?) -> Void)?
    var onTrackingModeChanged: ((Bool) -> Void)?

    var authorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }

    var isLocationServicesEnabled: Bool {
        CLLocationManager.locationServicesEnabled()
    }

    var hasCurrentLocationPermission: Bool {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        locationProcessingTask?.cancel()
        hybridTrackingWatchdogTask?.cancel()
        finalPreciseExitTask?.cancel()
        powerStateReevaluationTask?.cancel()
    }

    func configure(store: TravelsStore, settings: AppSettings, latestEvent: LocationEvent?) {
        self.store = store
        self.settings = settings
        self.latestAcceptedEvent = latestEvent
        let policy: LocationTrackingPolicy = settings.alwaysOnHighPrecisionLocation ? .alwaysOnHighPrecision : .hybridAutomatic
        self.trackingStateMachine = LocationTrackingStateMachine(policy: policy)
        self.hybridTrackingWatchdog.update(policy: policy)
        self.powerState = currentPowerState()
        locationManager.allowsBackgroundLocationUpdates = settings.backgroundLocationEnabled
        locationManager.showsBackgroundLocationIndicator = settings.backgroundLocationEnabled
        locationManager.activityType = .otherNavigation
        UIDevice.current.isBatteryMonitoringEnabled = true
        if !isConfigured {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(batteryStateDidChange(_:)),
                name: UIDevice.batteryStateDidChangeNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(powerStateDidChange(_:)),
                name: Notification.Name.NSProcessInfoPowerStateDidChange,
                object: nil
            )
            isConfigured = true
        }
        refreshAuthorization()
    }

    func update(settings: AppSettings) {
        self.settings = settings
        let policy: LocationTrackingPolicy = settings.alwaysOnHighPrecisionLocation ? .alwaysOnHighPrecision : .hybridAutomatic
        _ = trackingStateMachine.update(policy: policy)
        hybridTrackingWatchdog.update(policy: policy)
        powerState = currentPowerState()
        locationManager.allowsBackgroundLocationUpdates = settings.backgroundLocationEnabled
        locationManager.showsBackgroundLocationIndicator = settings.backgroundLocationEnabled
        refreshAuthorization()
    }

    func stop() {
        pendingManualCapture = false
        pendingForcedStoppedCapture = false
        isPausing = false
        cancelFinalPreciseExit()
        locationProcessingTask?.cancel()
        locationProcessingTask = nil
        cancelHybridTrackingWatchdog()
        powerStateReevaluationTask?.cancel()
        powerStateReevaluationTask = nil
        stopTrackingManager()
    }

    func requestCurrentLocation(forceStopped: Bool = false) {
        pendingManualCapture = true
        pendingForcedStoppedCapture = forceStopped
        if let location = locationManager.location {
            enqueue(location: location)
            return
        }
        locationManager.requestLocation()
    }

    private func refreshAuthorization() {
        guard settings.autoAddLocations else {
            pendingAlwaysAuthorization = false
            didScheduleAlwaysAuthorizationUpgrade = false
            cancelFinalPreciseExit()
            cancelHybridTrackingWatchdog()
            powerStateReevaluationTask?.cancel()
            powerStateReevaluationTask = nil
            stopTrackingManager()
            onAuthorizationStateChanged?(nil)
            return
        }

        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            pendingAlwaysAuthorization = false
            didScheduleAlwaysAuthorizationUpgrade = false
            onAuthorizationStateChanged?(nil)
            syncTrackingMode()
        case .authorizedWhenInUse:
            onAuthorizationStateChanged?(settings.backgroundLocationEnabled
                                         ? "Waiting for Always Location permission..."
                                         : nil)
            if settings.backgroundLocationEnabled {
                pendingAlwaysAuthorization = true
                scheduleAlwaysAuthorizationUpgrade()
            } else {
                pendingAlwaysAuthorization = false
                didScheduleAlwaysAuthorizationUpgrade = false
            }
            syncTrackingMode()
        case .notDetermined:
            pendingAlwaysAuthorization = settings.backgroundLocationEnabled
            didScheduleAlwaysAuthorizationUpgrade = false
            onAuthorizationStateChanged?(settings.backgroundLocationEnabled
                                         ? "Waiting for Always Location permission..."
                                         : "Waiting for Location permission...")
            if settings.backgroundLocationEnabled {
                locationManager.requestAlwaysAuthorization()
            } else {
                locationManager.requestWhenInUseAuthorization()
            }
        case .denied, .restricted:
            pendingAlwaysAuthorization = false
            didScheduleAlwaysAuthorizationUpgrade = false
            cancelFinalPreciseExit()
            cancelHybridTrackingWatchdog()
            powerStateReevaluationTask?.cancel()
            powerStateReevaluationTask = nil
            stopTrackingManager()
            onAuthorizationStateChanged?("Location access is needed for Travels.")
        @unknown default:
            break
        }
    }

    private func scheduleAlwaysAuthorizationUpgrade() {
        guard !didScheduleAlwaysAuthorizationUpgrade else { return }
        didScheduleAlwaysAuthorizationUpgrade = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(750))
            defer {
                self.pendingAlwaysAuthorization = false
                self.didScheduleAlwaysAuthorizationUpgrade = false
            }
            guard self.pendingAlwaysAuthorization else {
                return
            }
            guard self.locationManager.authorizationStatus == .authorizedWhenInUse else {
                return
            }
            self.locationManager.requestAlwaysAuthorization()
        }
    }

    private func updateDistanceFilter() {
        locationManager.distanceFilter = currentDistanceFilter()
    }

    private func updatePauseBehavior() {
        locationManager.pausesLocationUpdatesAutomatically = powerState.shouldPauseAutomatically
    }

    private func syncTrackingMode() {
        guard settings.autoAddLocations else {
            cancelFinalPreciseExit()
            cancelHybridTrackingWatchdog()
            stopTrackingManager()
            return
        }

        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
            cancelFinalPreciseExit()
            cancelHybridTrackingWatchdog()
            stopTrackingManager()
            return
        }

        let desiredMode: ManagerMode
        switch trackingStateMachine.state {
        case .idleDetection:
            desiredMode = .idleDetection
        case .activeTracking, .maybeStopped:
            desiredMode = .activeTracking
        }

        if desiredMode == .activeTracking, isCompletingHybridPreciseExit {
            cancelFinalPreciseExit(keepActiveTracking: true)
        } else if HybridPreciseLocationSamplingRules.shouldStartBoundedFinalPreciseExit(
            currentManagerIsActive: managerMode == .activeTracking,
            desiredIdleDetection: desiredMode == .idleDetection,
            isHybridPolicy: trackingStateMachine.policy == .hybridAutomatic,
            automaticLocationTrackingEnabled: settings.autoAddLocations,
            hasLocationAuthorization: authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse,
            isCompletingFinalPreciseExit: isCompletingHybridPreciseExit
        ) {
            beginFinalPreciseExit()
            return
        }

        applyTrackingMode(desiredMode)
    }

    private func applyTrackingMode(_ mode: ManagerMode) {
        if managerMode == mode {
            updateLocationManagerConfiguration(for: mode)
            updateHybridTrackingWatchdog(for: mode)
            notifyTrackingModeChanged()
            return
        }

        switch mode {
        case .stopped:
            cancelHybridTrackingWatchdog()
            stopTrackingManager()
        case .idleDetection:
            cancelHybridTrackingWatchdog()
            locationManager.stopUpdatingLocation()
            locationManager.startMonitoringSignificantLocationChanges()
            managerMode = .idleDetection
            updateLocationManagerConfiguration(for: mode)
            notifyTrackingModeChanged()
        case .activeTracking:
            locationManager.stopMonitoringSignificantLocationChanges()
            locationManager.startUpdatingLocation()
            managerMode = .activeTracking
            updateLocationManagerConfiguration(for: mode)
            traceLocationEvent("Entered precise location mode.")
            if HybridPreciseLocationSamplingRules.shouldRequestImmediateAutomaticSample(
                isEnteringActiveTracking: true,
                automaticLocationTrackingEnabled: settings.autoAddLocations,
                hasLocationAuthorization: authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse,
                isCompletingFinalPreciseExit: isCompletingHybridPreciseExit
            ) {
                requestAutomaticLocationSample(
                    reason: "Entered precise location mode; requesting an immediate automatic sample.",
                    useCachedLocationFirst: false
                )
            }
            updateHybridTrackingWatchdog(for: mode)
            notifyTrackingModeChanged()
        }
    }

    private func stopTrackingManager() {
        cancelFinalPreciseExit()
        cancelHybridTrackingWatchdog()
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.stopUpdatingLocation()
        managerMode = .stopped
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.pausesLocationUpdatesAutomatically = false
        notifyTrackingModeChanged()
    }

    private func updateLocationManagerConfiguration(for mode: ManagerMode) {
        switch mode {
        case .stopped:
            locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
            locationManager.distanceFilter = kCLDistanceFilterNone
            locationManager.pausesLocationUpdatesAutomatically = false
        case .idleDetection:
            locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
            locationManager.distanceFilter = kCLDistanceFilterNone
            locationManager.pausesLocationUpdatesAutomatically = false
        case .activeTracking:
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            updateDistanceFilter()
            updatePauseBehavior()
        }
    }

    private func currentDistanceFilter() -> CLLocationDistance {
        switch powerState.batteryState {
        case .charging, .full:
            return CLLocationDistance(settings.poweredUpdateDistanceMeters)
        case .unplugged, .unknown:
            return CLLocationDistance(settings.batteryUpdateDistanceMeters)
        @unknown default:
            return CLLocationDistance(settings.batteryUpdateDistanceMeters)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshAuthorization()
    }

    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        isPausing = true
        if settings.autoAddLocations && !isCompletingHybridPreciseExit {
            locationManager.requestLocation()
        }
    }

    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        isPausing = false
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError, clError.code == .locationUnknown {
            traceLocationEvent("Core Location reported locationUnknown after a request; waiting for the next sample.")
            return
        }
        if let clError = error as? CLError, clError.code == .denied {
            // Regression guard: denied authorization should surface the friendly access message
            // instead of leaking the raw kCLErrorDomain error back to the user.
            onAuthorizationStateChanged?("Location access is needed for Travels.")
            return
        }
        onStatusMessage?(error.localizedDescription)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            return
        }
        traceLocationEvent("Core Location delivered \(locations.count) update(s); using the newest sample.")
        if let ignoreUntil = ignoreAutomaticLocationUpdatesUntil, !pendingManualCapture {
            if Date() <= ignoreUntil {
                traceLocationEvent("Ignoring automatic location sample during post-precise-exit cooldown.")
                return
            }
            ignoreAutomaticLocationUpdatesUntil = nil
        }
        guard settings.autoAddLocations || pendingManualCapture else {
            return
        }
        enqueue(location: location)
    }

    @objc private func batteryStateDidChange(_ notification: Notification) {
        schedulePowerStateReevaluation()
    }

    @objc private func powerStateDidChange(_ notification: Notification) {
        schedulePowerStateReevaluation()
    }

    private func notifyTrackingModeChanged() {
        onTrackingModeChanged?(managerMode == .activeTracking)
    }

    private func currentPowerState() -> LocationTrackingPowerState {
        let batteryState: DeviceBatteryState
        switch UIDevice.current.batteryState {
        case .charging:
            batteryState = .charging
        case .full:
            batteryState = .full
        case .unplugged:
            batteryState = .unplugged
        case .unknown:
            batteryState = .unknown
        @unknown default:
            batteryState = .unknown
        }
        return LocationTrackingPowerState(
            batteryState: batteryState,
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

    private func schedulePowerStateReevaluation() {
        powerStateReevaluationTask?.cancel()
        powerStateReevaluationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            await MainActor.run {
                self?.reevaluatePowerState()
            }
        }
    }

    private func reevaluatePowerState() {
        let newPowerState = currentPowerState()
        guard newPowerState.requiresConfigurationRefresh(comparedTo: powerState) || managerMode == .activeTracking else {
            return
        }
        powerState = newPowerState
        syncTrackingMode()
    }

    private func updateHybridTrackingWatchdog(for mode: ManagerMode) {
        switch mode {
        case .activeTracking:
            guard !isCompletingHybridPreciseExit else { return }
            startHybridTrackingWatchdogIfNeeded()
        default:
            cancelHybridTrackingWatchdog()
        }
    }

    private func startHybridTrackingWatchdogIfNeeded() {
        guard settings.autoAddLocations else {
            cancelHybridTrackingWatchdog()
            return
        }
        guard trackingStateMachine.policy == .hybridAutomatic else {
            cancelHybridTrackingWatchdog()
            return
        }
        guard !isCompletingHybridPreciseExit else { return }
        guard managerMode == .activeTracking else { return }
        guard hybridTrackingWatchdogTask == nil else { return }
        hybridTrackingWatchdog.start(now: Date())
        guard hybridTrackingWatchdog.isRunning else { return }
        traceLocationEvent("Hybrid watchdog scheduled to request a fresh location sample in \(Int(hybridTrackingWatchdog.interval))s.")
        hybridTrackingWatchdogTask = Task { [weak self] in
            await self?.runHybridTrackingWatchdog()
        }
    }

    private func restartHybridTrackingWatchdog() {
        cancelHybridTrackingWatchdog()
        startHybridTrackingWatchdogIfNeeded()
    }

    private func cancelHybridTrackingWatchdog() {
        hybridTrackingWatchdogTask?.cancel()
        hybridTrackingWatchdogTask = nil
        hybridTrackingWatchdog.cancel()
    }

    private func runHybridTrackingWatchdog() async {
        defer { hybridTrackingWatchdogTask = nil }

        while !Task.isCancelled {
            guard case .scheduled(let nextRecheckAt) = hybridTrackingWatchdog.state else {
                return
            }

            let delay = max(0, nextRecheckAt.timeIntervalSinceNow)
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            guard settings.autoAddLocations else {
                cancelHybridTrackingWatchdog()
                return
            }
            guard managerMode == .activeTracking else {
                cancelHybridTrackingWatchdog()
                return
            }
            guard trackingStateMachine.policy == .hybridAutomatic else {
                cancelHybridTrackingWatchdog()
                return
            }
            guard hybridTrackingWatchdog.shouldRequestRecheck(now: Date()) else {
                continue
            }

            // BUGFIX: Hybrid tracking can go quiet after the user stops moving, so the watchdog
            // periodically uses the cached location first, then asks Core Location for one fresh
            // sample instead of waiting forever.
            if let location = locationManager.location {
                traceLocationEvent("Hybrid watchdog fired; using the cached location sample first.")
                // REGRESSION GUARD: when Core Location keeps returning the same cached position, the
                // watchdog still needs a fresh observation timestamp so repeated 90-second checks can
                // accumulate a real stationary window instead of reusing a stale sample time forever.
                enqueue(location: watchdogRecheckLocation(from: location))
                continue
            }
            requestAutomaticLocationSample(
                reason: "Hybrid watchdog fired; requesting a fresh location sample.",
                useCachedLocationFirst: false
            )
        }
    }

    private func requestAutomaticLocationSample(reason: String, useCachedLocationFirst: Bool) {
        guard settings.autoAddLocations else { return }
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else { return }
        traceLocationEvent(reason)
        if useCachedLocationFirst, let location = locationManager.location {
            traceLocationEvent("Hybrid tracking is using the cached location sample first; the sample remains automatic.")
            enqueue(location: watchdogRecheckLocation(from: location))
            return
        }
        locationManager.requestLocation()
    }

    private func beginFinalPreciseExit() {
        guard settings.autoAddLocations else { return }
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else { return }
        guard trackingStateMachine.policy == .hybridAutomatic else { return }
        guard managerMode == .activeTracking else { return }
        guard !isCompletingHybridPreciseExit else { return }

        isCompletingHybridPreciseExit = true
        ignoreAutomaticLocationUpdatesUntil = nil
        cancelHybridTrackingWatchdog()
        traceLocationEvent("Hybrid final precise exit started; waiting up to 8s for one bounded automatic sample.")

        if let location = locationManager.location {
            traceLocationEvent("Hybrid final precise exit is evaluating the cached location sample first; the sample remains automatic.")
            enqueue(location: location)
        } else {
            requestAutomaticLocationSample(
                reason: "Hybrid final precise exit requested a fresh automatic sample.",
                useCachedLocationFirst: false
            )
        }

        finalPreciseExitTask?.cancel()
        finalPreciseExitTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(8))
            } catch {
                return
            }
            await MainActor.run {
                self?.completeFinalPreciseExit(afterTimeout: true)
            }
        }
    }

    private func cancelFinalPreciseExit(keepActiveTracking: Bool = false) {
        guard isCompletingHybridPreciseExit || finalPreciseExitTask != nil else { return }
        isCompletingHybridPreciseExit = false
        finalPreciseExitTask?.cancel()
        finalPreciseExitTask = nil
        if !keepActiveTracking {
            ignoreAutomaticLocationUpdatesUntil = nil
        }
    }

    private func completeFinalPreciseExit(afterTimeout: Bool = false) {
        guard isCompletingHybridPreciseExit else { return }
        isCompletingHybridPreciseExit = false
        finalPreciseExitTask?.cancel()
        finalPreciseExitTask = nil
        ignoreAutomaticLocationUpdatesUntil = Date().addingTimeInterval(10)
        traceLocationEvent(afterTimeout
                           ? "Hybrid final precise exit timed out; returning to idle detection mode."
                           : "Hybrid final precise exit completed; returning to idle detection mode.")
        applyTrackingMode(.idleDetection)
    }

    private func watchdogRecheckLocation(from location: CLLocation) -> CLLocation {
        CLLocation(
            coordinate: location.coordinate,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy,
            course: location.course,
            speed: location.speed,
            timestamp: Date()
        )
    }

    private func enqueue(location: CLLocation) {
        pendingLocation = location
        guard locationProcessingTask == nil else { return }
        locationProcessingTask = Task { [weak self] in
            await self?.processPendingLocations()
        }
    }

    private func processPendingLocations() async {
        defer {
            locationProcessingTask = nil
        }

        while let location = pendingLocation {
            pendingLocation = nil
            await handle(location: location)
        }
    }

    private func handle(location: CLLocation) async {
        let wasManualCapture = pendingManualCapture
        let forceStoppedCapture = pendingForcedStoppedCapture
        let forceCapture = pendingManualCapture
        let wasCompletingFinalPreciseExit = isCompletingHybridPreciseExit
        pendingManualCapture = false
        pendingForcedStoppedCapture = false
        let sample = LocationSample(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            course: location.course,
            speed: forceStoppedCapture ? 0 : location.speed,
            timestamp: location.timestamp
        )

        var finalPreciseExitResumedMovement = false
        if wasCompletingFinalPreciseExit {
            traceLocationEvent("Final precise exit sample received.")
            let assessment = HybridPreciseLocationSamplingRules.finalPreciseExitSampleAssessment(
                sample: sample,
                latestAcceptedEvent: latestAcceptedEvent,
                stationarySpeedThreshold: trackingStateMachine.thresholds.stationarySpeedThreshold,
                stationaryRadiusMeters: trackingStateMachine.thresholds.stationaryRadiusMeters,
                minimumUsableHorizontalAccuracyMeters: trackingStateMachine.thresholds.minimumUsableHorizontalAccuracyMeters
            )
            switch assessment {
            case .movementResumed(let reason):
                finalPreciseExitResumedMovement = true
                traceLocationEvent("Final precise exit sample proves movement resumed (\(reason)); staying in active tracking.")
                cancelFinalPreciseExit(keepActiveTracking: true)
            case .confirmsStop(let reason):
                traceLocationEvent("Final precise exit sample accepted as stop confirmation (\(reason)).")
            case .rejects(let reason):
                traceLocationEvent("Final precise exit sample rejected as stale/low-accuracy/jitter (\(reason)); completing final precise exit.")
                completeFinalPreciseExit()
                if isPausing {
                    isPausing = false
                }
                return
            }
        }

        traceLocationEvent("Received location sample speed=\(formatSpeed(sample.speed)) accuracy=\(formatDistance(sample.horizontalAccuracy)) manual=\(wasManualCapture) forcedStopped=\(forceStoppedCapture) trackedMode=\(trackingModeLabel())")

        let previousTrackingState = trackingStateMachine.state
        if !wasManualCapture && (!wasCompletingFinalPreciseExit || finalPreciseExitResumedMovement) {
            if case .idleDetection = previousTrackingState {
                if trackingStateMachine.idleDetectionSampleIndicatesMovement(sample) {
                    traceLocationEvent("Idle detection sample qualifies for active tracking.")
                } else {
                    traceLocationEvent("Idle detection sample does not qualify for active tracking.")
                }
            }
            _ = trackingStateMachine.record(sample: sample)
            if let trackingStateMessage = trackingStateMessage(
                previous: previousTrackingState,
                current: trackingStateMachine.state
            ) {
                traceLocationEvent(trackingStateMessage)
            }
        }

        let decision = LocationFiltering.decision(
            candidate: sample,
            previous: latestAcceptedEvent,
            force: forceCapture,
            isPausing: isPausing,
            minimumDistanceMeters: Double(settings.poweredUpdateDistanceMeters),
            pausedMinimumDistanceMeters: 50
        )

        traceLocationEvent(locationDecisionMessage(for: decision, sample: sample, previous: latestAcceptedEvent, force: forceCapture, isPausing: isPausing))

        guard decision != .reject else {
            if wasCompletingFinalPreciseExit && !finalPreciseExitResumedMovement {
                completeFinalPreciseExit()
                if isPausing {
                    isPausing = false
                }
                return
            }
            if !wasManualCapture {
                syncTrackingMode()
            }
            return
        }

        var event = LocationFiltering.event(from: sample, source: .locationServices)
        if decision == .acceptAndReplacePrevious {
            event.geolocationID = latestAcceptedEvent?.geolocationID
        }
        do {
            let savedKind = decision == .acceptAndReplacePrevious ? "replacement" : "new"
            let eventID = try await save(
                event: event,
                replacingEventID: decision == .acceptAndReplacePrevious ? latestAcceptedEvent?.id : nil
            )
            traceLocationEvent("Saved location event #\(eventID) as \(savedKind) record.")
            if wasManualCapture, eventID > 0 {
                onManualTrackedEvent?(eventID, event.timestamp)
            }
        } catch {
            onStatusMessage?(error.localizedDescription)
        }

        if wasCompletingFinalPreciseExit && !finalPreciseExitResumedMovement {
            completeFinalPreciseExit()
            if isPausing {
                isPausing = false
            }
            return
        }

        if !wasManualCapture {
            restartHybridTrackingWatchdog()
            syncTrackingMode()
        }

        if isPausing {
            isPausing = false
        }
    }

    private func locationDecisionMessage(
        for decision: LocationFilterDecision,
        sample: LocationSample,
        previous: LocationEvent?,
        force: Bool,
        isPausing: Bool
    ) -> String {
        let timestamp = Self.traceDateFormatter.string(from: sample.timestamp)
        switch decision {
        case .accept:
            return "Location accepted @ \(timestamp): \(locationDecisionReason(candidate: sample, previous: previous, force: force, isPausing: isPausing, decision: decision))"
        case .acceptAndReplacePrevious:
            return "Location accepted and replaced previous event @ \(timestamp): \(locationDecisionReason(candidate: sample, previous: previous, force: force, isPausing: isPausing, decision: decision))"
        case .reject:
            return "Location rejected @ \(timestamp): \(locationDecisionReason(candidate: sample, previous: previous, force: force, isPausing: isPausing, decision: decision))"
        }
    }

    private func locationDecisionReason(
        candidate: LocationSample,
        previous: LocationEvent?,
        force: Bool,
        isPausing: Bool,
        decision: LocationFilterDecision
    ) -> String {
        guard !force else { return "manual capture requested" }
        guard let previous else { return "no previous event available" }

        let elapsed = candidate.timestamp.timeIntervalSince(previous.timestamp)
        if elapsed < 0 {
            return "candidate timestamp is older than the previous accepted event"
        }

        let distance = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
            .distance(from: CLLocation(latitude: candidate.latitude, longitude: candidate.longitude))

        if distance <= previous.horizontalAccuracy {
            if elapsed < 300 {
                let moreAccurate = candidate.horizontalAccuracy < previous.horizontalAccuracy
                let candidateSpeedUnavailable = !candidate.speed.isFinite || candidate.speed < 0
                let previousSpeedUnavailable = !previous.speed.isFinite || previous.speed < 0
                let atLeastAsAccurateAndSlower = candidate.horizontalAccuracy <= previous.horizontalAccuracy
                    && (
                        (candidate.speed >= 0 && previous.speed >= 0 && candidate.speed < previous.speed)
                        || (candidateSpeedUnavailable && previous.speed <= 0)
                        || (previousSpeedUnavailable && candidate.speed <= 0)
                    )
                if moreAccurate {
                    return "inside the previous event radius, more accurate, and within the improvement window"
                }
                if atLeastAsAccurateAndSlower {
                    return "inside the previous event radius, at least as accurate, slower or unavailable speed, and within the improvement window"
                }
            }
            return "inside the previous event radius without a qualifying improvement window"
        }

        if distance <= candidate.horizontalAccuracy {
            return "within the candidate accuracy radius"
        }

        if decision == .accept {
            let threshold = isPausing ? 50.0 : Double(settings.poweredUpdateDistanceMeters)
            return "moved \(String(format: "%.1fm", distance)) which meets the \(String(format: "%.1fm", threshold)) distance threshold"
        }

        return "did not meet the current filter rules"
    }

    private func trackingModeLabel() -> String {
        switch managerMode {
        case .activeTracking:
            return "active"
        case .idleDetection:
            return "idle"
        case .stopped:
            return "stopped"
        }
    }

    private func trackingStateMessage(
        previous: LocationTrackingState,
        current: LocationTrackingState
    ) -> String? {
        switch (previous, current) {
        case (.activeTracking, .maybeStopped(_, let samples)):
            return maybeStoppedEntryMessage(samples: samples)
        case (.maybeStopped, .maybeStopped(_, let samples)):
            return maybeStoppedProgressMessage(samples: samples)
        case (.maybeStopped, .activeTracking):
            return "Movement resumed; leaving the stationary window."
        case (.maybeStopped, .idleDetection):
            return "Stationary window satisfied; exiting precise location mode."
        default:
            return nil
        }
    }

    private func maybeStoppedEntryMessage(samples: [LocationSample]) -> String? {
        guard let message = maybeStoppedProgressMessage(samples: samples) else {
            return nil
        }
        return "Entered maybe-stopped mode; \(message)"
    }

    private func maybeStoppedProgressMessage(samples: [LocationSample]) -> String? {
        guard let first = samples.first, let last = samples.last else {
            return nil
        }
        let elapsed = max(0, last.timestamp.timeIntervalSince(first.timestamp))
        let duration = max(0, trackingStateMachine.thresholds.stationaryDuration)
        let remaining = max(0, duration - elapsed)
        return String(
            format: "Possible stop detected; stationary window elapsed=%.0fs remaining=%.0fs samples=%d.",
            elapsed,
            remaining,
            samples.count
        )
    }

    private func traceLocationEvent(_ message: String) {
        onTraceMessage?(message)
    }

    private func formatDistance(_ value: Double) -> String {
        guard value.isFinite else { return "unknown" }
        return String(format: "%.1fm", value)
    }

    private func formatSpeed(_ value: Double) -> String {
        guard value.isFinite else { return "unknown" }
        return String(format: "%.2fm/s", value)
    }

    private static let traceDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()

    private func save(event: LocationEvent, replacingEventID: Int64? = nil) async throws -> Int64 {
        guard let store else { return 0 }
        let eventID = try await Task.detached(priority: .utility) { [store, event] in
            if let replacingEventID {
                try store.replaceEvent(eventID: replacingEventID, with: event)
                return replacingEventID
            }
            return try store.saveEvent(event)
        }.value
        var storedEvent = event
        storedEvent.id = eventID
        latestAcceptedEvent = storedEvent
        onTrackedEvent?()
        return eventID
    }
}
