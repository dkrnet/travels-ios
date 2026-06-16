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

    private enum HybridWatchdogCancellationReason {
        case trackingStopped
        case automaticTrackingDisabled
        case authorizationUnavailable
        case managerModeChangedOutOfActiveTracking
        case preciseLocationModeChanged
        case trackingPolicyNotHybridAutomatic
        case finalPreciseExitStarted
        case finalPreciseExitCompleted
        case postExitGuardActive
        case powerStateSettingsReconfiguration
        case serviceDeinit
        case replacedByNewerTask
        case unknown

        var message: String {
            switch self {
            case .trackingStopped:
                "tracking stopped"
            case .automaticTrackingDisabled:
                "automatic tracking disabled"
            case .authorizationUnavailable:
                "authorization lost or not sufficient"
            case .managerModeChangedOutOfActiveTracking:
                "manager mode changed out of active tracking"
            case .preciseLocationModeChanged:
                "precise location mode changed"
            case .trackingPolicyNotHybridAutomatic:
                "tracking policy is not hybrid automatic"
            case .finalPreciseExitStarted:
                "final precise-exit started"
            case .finalPreciseExitCompleted:
                "final precise-exit completed"
            case .postExitGuardActive:
                "post-exit guard active"
            case .powerStateSettingsReconfiguration:
                "power-state/settings reconfiguration"
            case .serviceDeinit:
                "service deinit"
            case .replacedByNewerTask:
                "replaced by newer watchdog task"
            case .unknown:
                "unknown / defensive cleanup"
            }
        }
    }

    private struct PostExitPreciseGuard {
        let exitTimestamp: Date
        let finalExitSample: LocationSample?
        let reason: String
    }

    private struct ActiveTrackingEntryGuard {
        let enteredAt: Date
        let reason: String
        let entryLocation: LocationSample?
        var firstWatchdogRecheckCompleted: Bool
    }

    private struct PendingLocationContext {
        let reason: String
        let source: String
        let isCachedLocation: Bool
        let isImmediatePreciseEntrySample: Bool

        static let coreLocationUpdate = PendingLocationContext(
            reason: "Core Location update",
            source: "coreLocation",
            isCachedLocation: false,
            isImmediatePreciseEntrySample: false
        )
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
    private var pendingLocationContext: PendingLocationContext?
    private nonisolated(unsafe) var locationProcessingTask: Task<Void, Never>?
    private nonisolated(unsafe) var hybridTrackingWatchdogTask: Task<Void, Never>?
    private nonisolated(unsafe) var finalPreciseExitTask: Task<Void, Never>?
    private nonisolated(unsafe) var powerStateReevaluationTask: Task<Void, Never>?
    private nonisolated(unsafe) var activeHybridWatchdogID: Int?
    private var hybridTrackingWatchdog = HybridTrackingWatchdog()
    private var nextHybridWatchdogID = 1
    private var powerState = LocationTrackingPowerState()
    private var adaptiveDistanceCalculator = AdaptiveLocationDistanceCalculator()
    private var managerMode: ManagerMode = .stopped
    private var isCompletingHybridPreciseExit = false
    private var preciseModeEnteredAt: Date?
    private var activeTrackingEntryGuard: ActiveTrackingEntryGuard?
    private var pendingImmediatePreciseEntrySample = false
    private var ignoreAutomaticLocationUpdatesUntil: Date?
    private var postExitPreciseGuard: PostExitPreciseGuard?
    private var pendingFinalPreciseExitSample: LocationSample?
    private var lastNotifiedTrackingModeIsActive: Bool?

    private let postExitPreciseGuardCooldown: TimeInterval = 180
    private let minimumInitialActiveTrackingInterval: TimeInterval = 90
    private let maximumCachedWatchdogLocationAge: TimeInterval = 30

    var onStatusMessage: ((String) -> Void)?
    var onTraceMessage: ((String) -> Void)?
    var onTrackedEvent: (() -> Void)?
    var onManualTrackedEvent: ((Int64, Date) -> Void)?
    var onAuthorizationStateChanged: ((String?) -> Void)?
    var onTrackingModeChanged: ((Bool, String) -> Void)?
    var onAdaptiveDistanceChanged: ((Double) -> Void)?

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
        // Deinit is nonisolated under Swift 6, so this one cancellation cannot use the
        // MainActor trace callback. Keep an explicit system diagnostic before cancelling.
        if let activeHybridWatchdogID {
            NSLog("Hybrid watchdog #\(activeHybridWatchdogID) cancellation requested; reason=service deinit.")
        } else {
            NSLog("Hybrid watchdog cancellation requested with no running watchdog; reason=service deinit.")
        }
        NSLog("Initial active tracking guard cleared; reason=service deinit.")
        NSLog("Hybrid watchdog deinit clearing task reference; oldActiveWatchdogID=\(activeHybridWatchdogID.map(String.init) ?? "none") hadTask=\(hybridTrackingWatchdogTask != nil).")
        hybridTrackingWatchdogTask?.cancel()
        hybridTrackingWatchdogTask = nil
        NSLog("Hybrid watchdog deinit clearing active watchdog ID; oldActiveWatchdogID=\(activeHybridWatchdogID.map(String.init) ?? "none").")
        activeHybridWatchdogID = nil
        finalPreciseExitTask?.cancel()
        powerStateReevaluationTask?.cancel()
    }

    func configure(store: TravelsStore, settings: AppSettings, latestEvent: LocationEvent?) {
        self.store = store
        self.settings = settings
        self.latestAcceptedEvent = latestEvent
        let policy = settings.preciseLocationMode.locationTrackingPolicy
        self.trackingStateMachine = LocationTrackingStateMachine(policy: policy)
        self.hybridTrackingWatchdog.update(policy: policy)
        self.adaptiveDistanceCalculator = AdaptiveLocationDistanceCalculator(mode: settings.locationDetailMode)
        self.powerState = currentPowerState()
        self.lastNotifiedTrackingModeIsActive = nil
        locationManager.allowsBackgroundLocationUpdates = settings.backgroundLocationEnabled
        locationManager.showsBackgroundLocationIndicator = settings.backgroundLocationEnabled
        locationManager.activityType = .automotiveNavigation
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
        let previousLocationDetailMode = self.settings.locationDetailMode
        let previousPreciseLocationMode = self.settings.preciseLocationMode
        self.settings = settings
        let policy = settings.preciseLocationMode.locationTrackingPolicy
        _ = trackingStateMachine.update(policy: policy)
        hybridTrackingWatchdog.update(policy: policy)
        if previousPreciseLocationMode != settings.preciseLocationMode {
            clearActiveTrackingEntryGuard(reason: "Precise Location Mode changed")
            clearPostExitPreciseGuard(reason: "Precise Location Mode changed")
            cancelHybridTrackingWatchdog(reason: .preciseLocationModeChanged)
        } else if policy != .hybridAutomatic {
            clearActiveTrackingEntryGuard(reason: "tracking policy is not hybrid automatic")
            clearPostExitPreciseGuard(reason: "tracking policy is not hybrid automatic")
            cancelHybridTrackingWatchdog(reason: .trackingPolicyNotHybridAutomatic)
        }
        if previousLocationDetailMode != settings.locationDetailMode {
            adaptiveDistanceCalculator.update(mode: settings.locationDetailMode)
            if managerMode == .activeTracking {
                updateDistanceFilter()
            }
            onAdaptiveDistanceChanged?(currentAdaptiveDistanceMeters)
            traceLocationEvent("Location Detail changed to \(settings.locationDetailMode.displayName); adaptive distance is \(formatDistance(currentAdaptiveDistanceMeters)).")
        }
        powerState = currentPowerState()
        locationManager.allowsBackgroundLocationUpdates = settings.backgroundLocationEnabled
        locationManager.showsBackgroundLocationIndicator = settings.backgroundLocationEnabled
        refreshAuthorization()
    }

    func stop() {
        pendingManualCapture = false
        pendingForcedStoppedCapture = false
        isPausing = false
        clearActiveTrackingEntryGuard(reason: "tracking stopped")
        clearPostExitPreciseGuard(reason: "tracking stopped")
        cancelFinalPreciseExit()
        locationProcessingTask?.cancel()
        locationProcessingTask = nil
        cancelHybridTrackingWatchdog(reason: .trackingStopped)
        powerStateReevaluationTask?.cancel()
        powerStateReevaluationTask = nil
        adaptiveDistanceCalculator = AdaptiveLocationDistanceCalculator(mode: settings.locationDetailMode)
        onAdaptiveDistanceChanged?(currentAdaptiveDistanceMeters)
        stopTrackingManager()
    }

    func requestCurrentLocation(forceStopped: Bool = false) {
        pendingManualCapture = true
        pendingForcedStoppedCapture = forceStopped
        if let location = locationManager.location {
            enqueue(
                location: location,
                context: PendingLocationContext(
                    reason: forceStopped ? "Manual stopped capture using cached location" : "Manual capture using cached location",
                    source: "manualCapture",
                    isCachedLocation: true,
                    isImmediatePreciseEntrySample: false
                )
            )
            return
        }
        locationManager.requestLocation()
    }

    private func refreshAuthorization() {
        guard settings.autoAddLocations else {
            pendingAlwaysAuthorization = false
            didScheduleAlwaysAuthorizationUpgrade = false
            clearActiveTrackingEntryGuard(reason: "automatic tracking disabled")
            clearPostExitPreciseGuard(reason: "automatic tracking disabled")
            cancelFinalPreciseExit()
            cancelHybridTrackingWatchdog(reason: .automaticTrackingDisabled)
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
            clearActiveTrackingEntryGuard(reason: "authorization lost or not sufficient")
            clearPostExitPreciseGuard(reason: "authorization lost or not sufficient")
            cancelFinalPreciseExit()
            cancelHybridTrackingWatchdog(reason: .authorizationUnavailable)
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
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    private func syncTrackingMode() {
        guard settings.autoAddLocations else {
            clearActiveTrackingEntryGuard(reason: "automatic tracking disabled")
            clearPostExitPreciseGuard(reason: "automatic tracking disabled")
            cancelFinalPreciseExit()
            cancelHybridTrackingWatchdog(reason: .automaticTrackingDisabled)
            stopTrackingManager()
            return
        }

        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
            clearActiveTrackingEntryGuard(reason: "authorization lost or not sufficient")
            clearPostExitPreciseGuard(reason: "authorization lost or not sufficient")
            cancelFinalPreciseExit()
            cancelHybridTrackingWatchdog(reason: .authorizationUnavailable)
            stopTrackingManager()
            return
        }

        let desiredMode: ManagerMode
        switch trackingStateMachine.policy {
        case .alwaysOnHighPrecision:
            desiredMode = .activeTracking
        case .alwaysOffHighPrecision:
            desiredMode = .idleDetection
        case .hybridAutomatic:
            switch trackingStateMachine.state {
            case .idleDetection:
                desiredMode = .idleDetection
            case .activeTracking, .maybeStopped:
                desiredMode = .activeTracking
            }
        }

        if desiredMode == .activeTracking, isCompletingHybridPreciseExit {
            cancelFinalPreciseExit(keepActiveTracking: true)
        } else if desiredMode == .idleDetection {
            // REGRESSION GUARD: An idle-to-idle resync is not a precise-mode exit.
            // Late automatic samples can legitimately arrive while already idle; logging
            // those as exits made diagnostics look like precise mode had just been
            // downgraded before the watchdog could run.
            if managerMode == .idleDetection {
                updateLocationManagerConfiguration(for: .idleDetection)
                traceLocationEvent("syncTrackingMode kept idle detection; already idle, no precise-mode exit requested; reason=syncTrackingMode desired idle detection; \(hybridWatchdogContext()).")
                return
            }
            if HybridPreciseLocationSamplingRules.shouldStartBoundedFinalPreciseExit(
                currentManagerIsActive: managerMode == .activeTracking,
                desiredIdleDetection: true,
                isHybridPolicy: trackingStateMachine.policy == .hybridAutomatic,
                automaticLocationTrackingEnabled: settings.autoAddLocations,
                hasLocationAuthorization: authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse,
                isCompletingFinalPreciseExit: isCompletingHybridPreciseExit
            ) {
                beginFinalPreciseExit()
                return
            }
            requestIdleDowngrade(reason: "syncTrackingMode desired idle detection")
            return
        }

        applyTrackingMode(desiredMode)
    }

    private func applyTrackingMode(_ mode: ManagerMode) {
        if managerMode == mode {
            updateLocationManagerConfiguration(for: mode)
            if mode == .activeTracking {
                ensureActiveTrackingEntryGuardArmedIfNeeded(reason: "tracking mode reapplied while active")
            }
            updateHybridTrackingWatchdog(for: mode, reason: "tracking mode reapplied")
            notifyTrackingModeChanged(callSite: "applyTrackingMode same-mode reapply", reason: "tracking mode reapplied")
            return
        }

        switch mode {
        case .stopped:
            tracePreciseModeExitIfNeeded(callSite: "applyTrackingMode(.stopped)", reason: "tracking stopped")
            cancelHybridTrackingWatchdog(reason: .trackingStopped)
            stopTrackingManager()
        case .idleDetection:
            _ = requestIdleDowngrade(
                callSite: "applyTrackingMode(.idleDetection)",
                reason: "applyTrackingMode idle detection"
            )
        case .activeTracking:
            locationManager.stopMonitoringSignificantLocationChanges()
            locationManager.startUpdatingLocation()
            managerMode = .activeTracking
            updateLocationManagerConfiguration(for: mode)
            let enteredAt = Date()
            preciseModeEnteredAt = enteredAt
            ensureActiveTrackingEntryGuardArmedIfNeeded(
                enteredAt: enteredAt,
                reason: "tracking mode changed to active tracking"
            )
            let shouldRequestImmediateSample = HybridPreciseLocationSamplingRules.shouldRequestImmediateAutomaticSample(
                isEnteringActiveTracking: true,
                automaticLocationTrackingEnabled: settings.autoAddLocations,
                hasLocationAuthorization: authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse,
                isCompletingFinalPreciseExit: isCompletingHybridPreciseExit
            ) && trackingStateMachine.policy == .hybridAutomatic
            traceLocationEvent("Entered precise location mode; reason=tracking mode changed to active tracking immediateSampleRequested=\(shouldRequestImmediateSample) watchdogStartWillBeRequested=true enteredAt=\(Self.traceDateFormatter.string(from: enteredAt)); \(hybridWatchdogContext()).")
            if shouldRequestImmediateSample {
                pendingImmediatePreciseEntrySample = true
                requestAutomaticLocationSample(
                    reason: "Entered precise location mode; requesting an immediate automatic sample.",
                    useCachedLocationFirst: false
                )
            } else if trackingStateMachine.policy == .alwaysOffHighPrecision {
                traceLocationEvent("Precise location mode entry skipped because Precise Location Mode is Always Off.")
            }
            updateHybridTrackingWatchdog(for: mode, reason: "entered precise location mode")
            notifyTrackingModeChanged(callSite: "applyTrackingMode active tracking", reason: "entered precise location mode")
        }
    }

    private func stopTrackingManager() {
        traceLocationEvent("Direct idle apply bypassing guard; reason=explicit stop/disable: tracking manager stopped; \(hybridWatchdogContext()).")
        clearActiveTrackingEntryGuard(reason: "tracking manager stopped")
        clearPostExitPreciseGuard(reason: "tracking manager stopped")
        cancelFinalPreciseExit()
        cancelHybridTrackingWatchdog(reason: .trackingStopped)
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.stopUpdatingLocation()
        managerMode = .stopped
        preciseModeEnteredAt = nil
        activeTrackingEntryGuard = nil
        pendingImmediatePreciseEntrySample = false
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.pausesLocationUpdatesAutomatically = false
        notifyTrackingModeChanged(callSite: "stopTrackingManager", reason: "tracking manager stopped")
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
        CLLocationDistance(currentAdaptiveDistanceMeters)
    }

    private var currentAdaptiveDistanceMeters: Double {
        adaptiveDistanceCalculator.state.effectiveDistanceMeters
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
        let isImmediatePreciseEntrySample = pendingImmediatePreciseEntrySample && !pendingManualCapture
        if isImmediatePreciseEntrySample {
            pendingImmediatePreciseEntrySample = false
        }
        traceLocationEvent("Core Location delivered \(locations.count) update(s); using the newest sample; manual=\(pendingManualCapture) immediatePreciseEntrySample=\(isImmediatePreciseEntrySample) elapsedSincePreciseEntry=\(preciseModeElapsedDescription()).")
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
        enqueue(
            location: location,
            context: PendingLocationContext(
                reason: isImmediatePreciseEntrySample ? "Immediate automatic sample after entering precise mode" : "Core Location update",
                source: "coreLocation",
                isCachedLocation: false,
                isImmediatePreciseEntrySample: isImmediatePreciseEntrySample
            )
        )
    }

    @objc private func batteryStateDidChange(_ notification: Notification) {
        schedulePowerStateReevaluation()
    }

    @objc private func powerStateDidChange(_ notification: Notification) {
        schedulePowerStateReevaluation()
    }

    private func notifyTrackingModeChanged(callSite: String = #function, reason: String = "tracking mode changed") {
        let isActive = managerMode == .activeTracking
        let context = "callSite=\(callSite) reason=\(reason) isActive=\(isActive) \(hybridWatchdogContext())"
        guard lastNotifiedTrackingModeIsActive != isActive else {
            traceLocationEvent("Tracking mode notification suppressed because active state did not change; \(context).")
            return
        }
        lastNotifiedTrackingModeIsActive = isActive
        traceLocationEvent("Tracking mode notification emitted; \(context).")
        onTrackingModeChanged?(isActive, context)
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

    private func updateHybridTrackingWatchdog(for mode: ManagerMode, reason: String) {
        traceLocationEvent("Hybrid watchdog update requested; reason=\(reason) mode=\(managerModeLabel(mode)) taskExists=\(hybridTrackingWatchdogTask != nil); \(hybridWatchdogContext()).")
        switch mode {
        case .activeTracking:
            guard !isCompletingHybridPreciseExit else {
                traceLocationEvent("Hybrid watchdog schedule skipped because final precise-exit is in progress; reason=\(reason); \(hybridWatchdogContext()).")
                return
            }
            startHybridTrackingWatchdogIfNeeded(reason: reason)
        default:
            cancelHybridTrackingWatchdog(reason: .managerModeChangedOutOfActiveTracking)
        }
    }

    private func startHybridTrackingWatchdogIfNeeded(reason: String) {
        traceLocationEvent("Hybrid watchdog start requested; reason=\(reason) taskExists=\(hybridTrackingWatchdogTask != nil); \(hybridWatchdogStateDescription()); \(hybridWatchdogContext()).")
        guard settings.autoAddLocations else {
            traceLocationEvent("Hybrid watchdog start guard skipped because Automatic Tracking is off; reason=\(reason); \(hybridWatchdogContext()).")
            cancelHybridTrackingWatchdog(reason: .automaticTrackingDisabled)
            return
        }
        guard trackingStateMachine.policy == .hybridAutomatic else {
            traceLocationEvent("Hybrid watchdog start guard skipped because tracking policy is \(trackingStateMachine.policy.rawValue); reason=\(reason); \(hybridWatchdogContext()).")
            cancelHybridTrackingWatchdog(reason: .trackingPolicyNotHybridAutomatic)
            return
        }
        guard !isCompletingHybridPreciseExit else {
            traceLocationEvent("Hybrid watchdog start guard skipped because final precise-exit is in progress; reason=\(reason); \(hybridWatchdogContext()).")
            return
        }
        guard managerMode == .activeTracking else {
            traceLocationEvent("Hybrid watchdog start guard skipped because manager mode is \(managerModeLabel()); reason=\(reason); \(hybridWatchdogContext()).")
            return
        }
        if activeTrackingEntryGuard == nil {
            traceLocationEvent("Hybrid watchdog start requested while initial active tracking guard is inactive; this is suspicious during hybrid active entry; reason=\(reason); \(hybridWatchdogContext()).")
        }
        guard hybridTrackingWatchdogTask == nil else {
            if let activeHybridWatchdogID {
                traceLocationEvent("Hybrid watchdog #\(activeHybridWatchdogID) start request ignored because a watchdog task is already running; reason=\(reason); existing task was not replaced; \(hybridWatchdogContext()).")
            } else {
                traceLocationEvent("Hybrid watchdog start request ignored because a watchdog task is already running but no active watchdog ID is recorded; reason=\(reason); existing task was not replaced; \(hybridWatchdogContext()).")
            }
            return
        }
        let scheduledAt = Date()
        hybridTrackingWatchdog.start(now: scheduledAt)
        guard hybridTrackingWatchdog.isRunning else {
            traceLocationEvent("Hybrid watchdog start request did not start a running watchdog; reason=\(reason); \(hybridWatchdogContext()).")
            return
        }
        let watchdogID = nextHybridWatchdogID
        nextHybridWatchdogID += 1
        traceLocationEvent("Hybrid watchdog #\(watchdogID) assigned; reason=\(reason) nextWatchdogID=\(nextHybridWatchdogID); \(hybridWatchdogContext()).")
        activeHybridWatchdogID = watchdogID
        traceLocationEvent("Hybrid watchdog #\(watchdogID) stored as active ID before task creation; reason=\(reason); \(hybridWatchdogContext()).")
        let nextFireDescription = hybridWatchdogNextFireDescription()
        traceLocationEvent("Hybrid watchdog #\(watchdogID) scheduled; interval=\(formatDuration(hybridTrackingWatchdog.interval)) nextFire=\(nextFireDescription); \(hybridWatchdogContext()).")
        traceLocationEvent("Hybrid watchdog #\(watchdogID) creating task; scheduledAt=\(Self.traceDateFormatter.string(from: scheduledAt)) nextFire=\(nextFireDescription); \(hybridWatchdogContext()).")
        hybridTrackingWatchdogTask = Task { [weak self] in
            await self?.runHybridTrackingWatchdog(id: watchdogID)
        }
        traceLocationEvent("Hybrid watchdog #\(watchdogID) task stored; taskExists=\(hybridTrackingWatchdogTask != nil) scheduledAt=\(Self.traceDateFormatter.string(from: scheduledAt)) nextFire=\(nextFireDescription); \(hybridWatchdogContext()).")
    }

    private func restartHybridTrackingWatchdog(reason: String) {
        let oldID = activeHybridWatchdogID
        let newID = nextHybridWatchdogID
        if let oldID {
            traceLocationEvent("Hybrid watchdog #\(oldID) replacement requested; reason=\(reason) scheduling watchdog #\(newID); \(hybridWatchdogContext()).")
        } else {
            traceLocationEvent("Hybrid watchdog replacement requested with no active watchdog ID; reason=\(reason) scheduling watchdog #\(newID); \(hybridWatchdogContext()).")
        }
        cancelHybridTrackingWatchdog(reason: .replacedByNewerTask)
        startHybridTrackingWatchdogIfNeeded(reason: reason)
    }

    private func cancelHybridTrackingWatchdog(reason: HybridWatchdogCancellationReason) {
        let hadTask = hybridTrackingWatchdogTask != nil
        let wasRunning = hybridTrackingWatchdog.isRunning
        if let activeHybridWatchdogID {
            traceLocationEvent("Hybrid watchdog #\(activeHybridWatchdogID) cancellation requested; reason=\(reason.message); hadTask=\(hadTask) wasRunning=\(wasRunning); \(hybridWatchdogContext()).")
        } else {
            traceLocationEvent("Hybrid watchdog cancellation requested with no running watchdog; reason=\(reason.message); hadTask=\(hadTask) wasRunning=\(wasRunning); \(hybridWatchdogContext()).")
        }
        hybridTrackingWatchdogTask?.cancel()
        traceLocationEvent("Hybrid watchdog task reference clearing; reason=\(reason.message) oldActiveWatchdogID=\(activeHybridWatchdogID.map(String.init) ?? "none") hadTask=\(hadTask) wasRunning=\(wasRunning); \(hybridWatchdogContext()).")
        hybridTrackingWatchdogTask = nil
        traceLocationEvent("Hybrid watchdog active ID clearing; reason=\(reason.message) oldActiveWatchdogID=\(activeHybridWatchdogID.map(String.init) ?? "none") hadTask=\(hadTask) wasRunning=\(wasRunning); \(hybridWatchdogContext()).")
        activeHybridWatchdogID = nil
        hybridTrackingWatchdog.cancel()
        traceLocationEvent("Hybrid watchdog cancelled and cleared; reason=\(reason.message); \(hybridWatchdogStateDescription()); \(hybridWatchdogContext()).")
    }

    private func runHybridTrackingWatchdog(id watchdogID: Int) async {
        var exitReason = "normal end"
        traceLocationEvent("Hybrid watchdog #\(watchdogID) task closure started; first line inside task; \(hybridWatchdogStateDescription()); \(hybridWatchdogContext()).")
        defer {
            if activeHybridWatchdogID == watchdogID {
                traceLocationEvent("Hybrid watchdog #\(watchdogID) task exited; reason=\(exitReason); clearing own task and active watchdog references; \(hybridWatchdogStateDescription()); \(hybridWatchdogContext()).")
                hybridTrackingWatchdogTask = nil
                traceLocationEvent("Hybrid watchdog #\(watchdogID) task reference cleared by owning task; reason=\(exitReason); \(hybridWatchdogStateDescription()); \(hybridWatchdogContext()).")
                activeHybridWatchdogID = nil
                traceLocationEvent("Hybrid watchdog #\(watchdogID) active watchdog ID cleared by owning task; reason=\(exitReason); \(hybridWatchdogStateDescription()); \(hybridWatchdogContext()).")
            } else if let activeHybridWatchdogID {
                traceLocationEvent("Hybrid watchdog #\(watchdogID) stale task exited; reason=\(exitReason); active watchdog is #\(activeHybridWatchdogID), so stale task did not clear task or active ID references; \(hybridWatchdogStateDescription()); \(hybridWatchdogContext()).")
            } else {
                traceLocationEvent("Hybrid watchdog #\(watchdogID) task exited; reason=\(exitReason); no active watchdog reference remains, so task did not clear a newer watchdog; \(hybridWatchdogStateDescription()); \(hybridWatchdogContext()).")
            }
        }

        while !Task.isCancelled {
            guard case .scheduled(let nextRecheckAt) = hybridTrackingWatchdog.state else {
                exitReason = "watchdog state is no longer scheduled"
                return
            }

            let delay = max(0, nextRecheckAt.timeIntervalSinceNow)
            traceLocationEvent("Hybrid watchdog #\(watchdogID) task sleeping for \(formatDuration(delay)); scheduledFire=\(Self.traceDateFormatter.string(from: nextRecheckAt)); \(hybridWatchdogContext()).")
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                exitReason = "cancelled while sleeping before scheduled fire"
                traceLocationEvent("Hybrid watchdog #\(watchdogID) sleep returned due to cancellation before scheduled fire; scheduledFire=\(Self.traceDateFormatter.string(from: nextRecheckAt)); \(hybridWatchdogContext()).")
                return
            }
            traceLocationEvent("Hybrid watchdog #\(watchdogID) sleep returned normally; scheduledFire=\(Self.traceDateFormatter.string(from: nextRecheckAt)); \(hybridWatchdogContext()).")

            guard !Task.isCancelled else {
                exitReason = "cancelled after sleep returned"
                traceLocationEvent("Hybrid watchdog #\(watchdogID) task observed cancellation after sleep returned; ending without firing; \(hybridWatchdogContext()).")
                return
            }
            guard settings.autoAddLocations else {
                exitReason = "guard skip: automatic tracking disabled"
                traceLocationEvent("Hybrid watchdog #\(watchdogID) skipped; automatic tracking disabled; \(hybridWatchdogContext()).")
                cancelHybridTrackingWatchdog(reason: .automaticTrackingDisabled)
                return
            }
            guard managerMode == .activeTracking else {
                exitReason = "guard skip: manager mode is \(managerModeLabel())"
                traceLocationEvent("Hybrid watchdog #\(watchdogID) skipped; manager mode is \(managerModeLabel()), not active tracking; \(hybridWatchdogContext()).")
                cancelHybridTrackingWatchdog(reason: .managerModeChangedOutOfActiveTracking)
                return
            }
            guard trackingStateMachine.policy == .hybridAutomatic else {
                exitReason = "guard skip: tracking policy is \(trackingStateMachine.policy.rawValue)"
                traceLocationEvent("Hybrid watchdog #\(watchdogID) skipped; tracking policy is \(trackingStateMachine.policy.rawValue), not hybridAutomatic; \(hybridWatchdogContext()).")
                cancelHybridTrackingWatchdog(reason: .trackingPolicyNotHybridAutomatic)
                return
            }
            guard !isCompletingHybridPreciseExit else {
                exitReason = "guard skip: final precise-exit in progress"
                traceLocationEvent("Hybrid watchdog #\(watchdogID) skipped; final precise-exit is in progress; \(hybridWatchdogContext()).")
                cancelHybridTrackingWatchdog(reason: .finalPreciseExitStarted)
                return
            }
            if let ignoreUntil = ignoreAutomaticLocationUpdatesUntil, Date() <= ignoreUntil {
                exitReason = "guard skip: post-exit cooldown active"
                traceLocationEvent("Hybrid watchdog #\(watchdogID) skipped; post-exit automatic sample cooldown is active until \(Self.traceDateFormatter.string(from: ignoreUntil)); \(hybridWatchdogContext()).")
                cancelHybridTrackingWatchdog(reason: .postExitGuardActive)
                return
            }
            let firedAt = Date()
            guard hybridTrackingWatchdog.shouldRequestRecheck(now: firedAt) else {
                traceLocationEvent("Hybrid watchdog #\(watchdogID) woke but no recheck was due; \(hybridWatchdogStateDescription()); \(hybridWatchdogContext()).")
                continue
            }
            markInitialActiveTrackingWatchdogRecheckCompleted(watchdogID: watchdogID)

            let elapsed = max(0, firedAt.timeIntervalSince(nextRecheckAt.addingTimeInterval(-hybridTrackingWatchdog.interval)))
            if let location = locationManager.location {
                let cachedAge = max(0, firedAt.timeIntervalSince(location.timestamp))
                if cachedAge <= maximumCachedWatchdogLocationAge {
                    traceLocationEvent(
                        "Hybrid watchdog #\(watchdogID) fired after \(formatDuration(elapsed)); using fresh-enough cached location sample; cachedAge=\(formatDuration(cachedAge)) timestamp=\(Self.traceDateFormatter.string(from: location.timestamp)) speed=\(formatSpeed(location.speed)) accuracy=\(formatDistance(location.horizontalAccuracy)); \(hybridWatchdogContext())."
                    )
                    enqueue(
                        location: location,
                        context: PendingLocationContext(
                            reason: "Hybrid watchdog #\(watchdogID) fired and used fresh-enough cached location",
                            source: "hybridWatchdog",
                            isCachedLocation: true,
                            isImmediatePreciseEntrySample: false
                        )
                    )
                    continue
                }
                traceLocationEvent(
                    "Hybrid watchdog #\(watchdogID) fired after \(formatDuration(elapsed)); cached location is stale, so requesting fresh location instead; cachedAge=\(formatDuration(cachedAge)) maxAllowedAge=\(formatDuration(maximumCachedWatchdogLocationAge)) timestamp=\(Self.traceDateFormatter.string(from: location.timestamp)) speed=\(formatSpeed(location.speed)) accuracy=\(formatDistance(location.horizontalAccuracy)); \(hybridWatchdogContext())."
                )
            }
            traceLocationEvent("Hybrid watchdog #\(watchdogID) fired after \(formatDuration(elapsed)); requesting fresh location with requestLocation(); \(hybridWatchdogContext()).")
            requestAutomaticLocationSample(
                reason: "Hybrid watchdog #\(watchdogID) fired; requesting a fresh location sample with requestLocation().",
                useCachedLocationFirst: false
            )
        }
        exitReason = "cancelled"
    }

    private func requestAutomaticLocationSample(reason: String, useCachedLocationFirst: Bool) {
        guard settings.autoAddLocations else { return }
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else { return }
        guard trackingStateMachine.policy != .alwaysOffHighPrecision else {
            traceLocationEvent("Automatic location sample skipped because Precise Location Mode is Always Off.")
            return
        }
        traceLocationEvent(reason)
        if useCachedLocationFirst, let location = locationManager.location {
            let cachedAge = max(0, Date().timeIntervalSince(location.timestamp))
            if cachedAge <= maximumCachedWatchdogLocationAge {
                traceLocationEvent(
                    "Hybrid tracking is using a fresh-enough cached location sample first; cachedAge=\(formatDuration(cachedAge)) timestamp=\(Self.traceDateFormatter.string(from: location.timestamp)) speed=\(formatSpeed(location.speed)) accuracy=\(formatDistance(location.horizontalAccuracy)); the sample remains automatic."
                )
                enqueue(
                    location: location,
                    context: PendingLocationContext(
                        reason: "\(reason) Used fresh-enough cached location first.",
                        source: "automaticRequest",
                        isCachedLocation: true,
                        isImmediatePreciseEntrySample: false
                    )
                )
                return
            }
            traceLocationEvent(
                "Hybrid tracking skipped cached location because it is stale; requesting fresh location instead; cachedAge=\(formatDuration(cachedAge)) maxAllowedAge=\(formatDuration(maximumCachedWatchdogLocationAge)) timestamp=\(Self.traceDateFormatter.string(from: location.timestamp)) speed=\(formatSpeed(location.speed)) accuracy=\(formatDistance(location.horizontalAccuracy))."
            )
        }
        locationManager.requestLocation()
    }

    private func beginFinalPreciseExit() {
        guard settings.autoAddLocations else { return }
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else { return }
        guard trackingStateMachine.policy == .hybridAutomatic else { return }
        guard managerMode == .activeTracking else { return }
        guard !isCompletingHybridPreciseExit else { return }
        guard shouldAllowIdleDowngrade(callSite: "beginFinalPreciseExit", reason: "begin final precise exit") else {
            traceLocationEvent("Final precise-exit deferred; initial active tracking guard is active; \(hybridWatchdogContext()).")
            notifyTrackingModeChanged(callSite: "beginFinalPreciseExit", reason: "final precise-exit deferred by initial guard")
            return
        }

        isCompletingHybridPreciseExit = true
        ignoreAutomaticLocationUpdatesUntil = nil
        pendingFinalPreciseExitSample = nil
        cancelHybridTrackingWatchdog(reason: .finalPreciseExitStarted)
        traceLocationEvent("Hybrid final precise exit started; waiting up to 8s for one bounded automatic sample.")

        if let location = locationManager.location {
            traceLocationEvent("Hybrid final precise exit is evaluating the cached location sample first; the sample remains automatic.")
            enqueue(
                location: location,
                context: PendingLocationContext(
                    reason: "Final precise exit evaluating cached location",
                    source: "finalPreciseExit",
                    isCachedLocation: true,
                    isImmediatePreciseEntrySample: false
                )
            )
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
        pendingFinalPreciseExitSample = nil
        finalPreciseExitTask?.cancel()
        finalPreciseExitTask = nil
        if !keepActiveTracking {
            ignoreAutomaticLocationUpdatesUntil = nil
        } else {
            traceLocationEvent("Final precise-exit cancelled because movement resumed; post-exit precise guard was not armed.")
        }
    }

    private func completeFinalPreciseExit(afterTimeout: Bool = false) {
        guard isCompletingHybridPreciseExit else { return }
        let exitReason = afterTimeout ? "final precise exit timed out" : "final precise exit completed"
        guard shouldAllowIdleDowngrade(callSite: "completeFinalPreciseExit", reason: exitReason) else {
            traceLocationEvent("Final precise-exit deferred; initial active tracking guard is active; reason=\(exitReason); \(hybridWatchdogContext()).")
            cancelFinalPreciseExit(keepActiveTracking: true)
            updateHybridTrackingWatchdog(
                for: .activeTracking,
                reason: "final precise-exit completion deferred by initial active tracking guard"
            )
            notifyTrackingModeChanged(callSite: "completeFinalPreciseExit", reason: "final precise-exit completion deferred by initial guard")
            return
        }
        cancelHybridTrackingWatchdog(reason: .finalPreciseExitCompleted)
        isCompletingHybridPreciseExit = false
        finalPreciseExitTask?.cancel()
        finalPreciseExitTask = nil
        ignoreAutomaticLocationUpdatesUntil = Date().addingTimeInterval(10)
        armPostExitPreciseGuard(
            finalExitSample: pendingFinalPreciseExitSample ?? latestAcceptedEvent.map(locationSample),
            reason: afterTimeout ? "final precise exit timed out" : "final precise exit completed"
        )
        pendingFinalPreciseExitSample = nil
        traceLocationEvent(afterTimeout
                           ? "Hybrid final precise exit timed out; returning to idle detection mode."
                           : "Hybrid final precise exit completed; returning to idle detection mode.")
        applyIdleDetectionModeBypassingGuard(
            callSite: "completeFinalPreciseExit",
            reason: exitReason
        )
    }

    private func ensureActiveTrackingEntryGuardArmedIfNeeded(
        callSite: String = #function,
        enteredAt: Date? = nil,
        reason: String
    ) {
        traceLocationEvent("Initial active tracking guard arm requested; callSite=\(callSite); reason=\(reason); \(hybridWatchdogContext()).")
        guard trackingStateMachine.policy == .hybridAutomatic else {
            traceLocationEvent("Initial active tracking guard not armed; callSite=\(callSite); reason=tracking policy is \(trackingStateMachine.policy.rawValue); \(hybridWatchdogContext()).")
            clearActiveTrackingEntryGuard(callSite: callSite, reason: "tracking policy is \(trackingStateMachine.policy.rawValue)")
            return
        }
        guard settings.autoAddLocations else {
            traceLocationEvent("Initial active tracking guard not armed; callSite=\(callSite); reason=Automatic Tracking is off; \(hybridWatchdogContext()).")
            clearActiveTrackingEntryGuard(callSite: callSite, reason: "automatic tracking disabled")
            return
        }
        guard managerMode == .activeTracking else {
            traceLocationEvent("Initial active tracking guard not armed; callSite=\(callSite); reason=manager mode is \(managerModeLabel()), not active; \(hybridWatchdogContext()).")
            return
        }
        if activeTrackingEntryGuard != nil {
            traceLocationEvent("Initial active tracking guard already active; not rearming; callSite=\(callSite); reason=\(reason); \(hybridWatchdogContext()).")
            return
        }
        armActiveTrackingEntryGuard(
            callSite: callSite,
            enteredAt: enteredAt ?? preciseModeEnteredAt ?? Date(),
            reason: reason,
            entryLocation: latestAcceptedEvent.map(locationSample)
        )
    }

    private func armActiveTrackingEntryGuard(
        callSite: String,
        enteredAt: Date,
        reason: String,
        entryLocation: LocationSample?
    ) {
        activeTrackingEntryGuard = ActiveTrackingEntryGuard(
            enteredAt: enteredAt,
            reason: reason,
            entryLocation: entryLocation,
            firstWatchdogRecheckCompleted: false
        )
        let locationDescription: String
        if let entryLocation {
            locationDescription = String(
                format: " entryLocation=(%.6f, %.6f) entryLocationAt=%@",
                entryLocation.latitude,
                entryLocation.longitude,
                Self.traceDateFormatter.string(from: entryLocation.timestamp)
            )
        } else {
            locationDescription = " entryLocation=unavailable"
        }
        traceLocationEvent("Initial active tracking guard armed; callSite=\(callSite); enteredAt=\(Self.traceDateFormatter.string(from: enteredAt)) reason=\(reason) minimumActiveInterval=\(formatDuration(minimumInitialActiveTrackingInterval))\(locationDescription).")
    }

    private func clearActiveTrackingEntryGuard(callSite: String = #function, reason: String) {
        traceLocationEvent("Initial active tracking guard clear requested; callSite=\(callSite); reason=\(reason); \(hybridWatchdogContext()).")
        guard activeTrackingEntryGuard != nil else {
            traceLocationEvent("Initial active tracking guard clear ignored; guard already inactive; callSite=\(callSite); reason=\(reason); \(hybridWatchdogContext()).")
            return
        }
        activeTrackingEntryGuard = nil
        traceLocationEvent("Initial active tracking guard cleared; callSite=\(callSite); reason=\(reason); \(hybridWatchdogContext()).")
    }

    private func markInitialActiveTrackingWatchdogRecheckCompleted(watchdogID: Int) {
        guard var guardState = activeTrackingEntryGuard,
              !guardState.firstWatchdogRecheckCompleted
        else {
            return
        }
        guardState.firstWatchdogRecheckCompleted = true
        activeTrackingEntryGuard = guardState
        let elapsed = Date().timeIntervalSince(guardState.enteredAt)
        traceLocationEvent("Initial active tracking guard satisfied; first watchdog recheck completed by watchdog #\(watchdogID) after \(formatDuration(elapsed)).")
    }

    @discardableResult
    private func requestIdleDowngrade(callSite: String = #function, reason: String, explicitStopOrDisable: Bool = false) -> Bool {
        traceLocationEvent("Precise mode exit requested; callSite=\(callSite); reason=\(reason) explicitStopOrDisable=\(explicitStopOrDisable); \(hybridWatchdogContext()).")
        guard shouldAllowIdleDowngrade(callSite: callSite, reason: reason, explicitStopOrDisable: explicitStopOrDisable) else {
            traceLocationEvent("Precise mode exit suppressed; initial active tracking guard is active; callSite=\(callSite); reason=\(reason); \(hybridWatchdogContext()).")
            notifyTrackingModeChanged(callSite: callSite, reason: "precise mode exit suppressed")
            return false
        }
        traceLocationEvent("Precise mode exit allowed; callSite=\(callSite); reason=\(reason); \(hybridWatchdogContext()).")
        applyIdleDetectionModeBypassingGuard(callSite: callSite, reason: reason)
        return true
    }

    private func applyIdleDetectionModeBypassingGuard(callSite: String, reason: String) {
        traceLocationEvent("Direct idle apply bypassing guard; callSite=\(callSite); reason=central idle downgrade helper allowed: \(reason); \(hybridWatchdogContext()).")
        tracePreciseModeExitIfNeeded(callSite: callSite, reason: reason)
        cancelHybridTrackingWatchdog(reason: .managerModeChangedOutOfActiveTracking)
        locationManager.stopUpdatingLocation()
        locationManager.startMonitoringSignificantLocationChanges()
        managerMode = .idleDetection
        preciseModeEnteredAt = nil
        clearActiveTrackingEntryGuard(callSite: callSite, reason: "precise mode exited to idle detection")
        pendingImmediatePreciseEntrySample = false
        updateLocationManagerConfiguration(for: .idleDetection)
        notifyTrackingModeChanged(callSite: callSite, reason: reason)
    }

    private func shouldAllowIdleDowngrade(callSite: String = #function, reason: String, explicitStopOrDisable: Bool = false) -> Bool {
        traceLocationEvent("Idle downgrade requested; callSite=\(callSite); reason=\(reason) explicitStopOrDisable=\(explicitStopOrDisable); \(hybridWatchdogContext()).")
        if explicitStopOrDisable {
            traceLocationEvent("Idle downgrade bypassed guard; callSite=\(callSite); reason=explicit stop/disable: \(reason); \(hybridWatchdogContext()).")
            traceLocationEvent("Idle downgrade allowed; reason=explicit stop/disable; requestReason=\(reason); \(hybridWatchdogContext()).")
            clearActiveTrackingEntryGuard(callSite: callSite, reason: reason)
            return true
        }
        guard let guardState = activeTrackingEntryGuard else {
            traceLocationEvent("Initial active tracking guard not active during idle downgrade request; callSite=\(callSite); reason=\(reason); \(hybridWatchdogContext()).")
            traceLocationEvent("Idle downgrade evaluated guard; callSite=\(callSite); allowed=true; reason=initial guard inactive; requestReason=\(reason); \(hybridWatchdogContext()).")
            traceLocationEvent("Idle downgrade allowed; reason=initial guard inactive; requestReason=\(reason); \(hybridWatchdogContext()).")
            return true
        }
        guard trackingStateMachine.policy == .hybridAutomatic,
              managerMode == .activeTracking
        else {
            traceLocationEvent("Idle downgrade evaluated guard; callSite=\(callSite); allowed=true; reason=guard no longer applies; requestReason=\(reason); \(hybridWatchdogContext()).")
            traceLocationEvent("Idle downgrade allowed; reason=guard no longer applies; requestReason=\(reason); \(hybridWatchdogContext()).")
            clearActiveTrackingEntryGuard(callSite: callSite, reason: "policy or manager mode no longer uses hybrid active tracking")
            return true
        }
        let status = HybridPreciseLocationSamplingRules.initialActiveTrackingGuardStatus(
            enteredAt: guardState.enteredAt,
            firstWatchdogRecheckCompleted: guardState.firstWatchdogRecheckCompleted,
            minimumActiveInterval: minimumInitialActiveTrackingInterval
        )
        if status.isActive {
            let elapsed = Date().timeIntervalSince(guardState.enteredAt)
            traceLocationEvent("Idle downgrade evaluated guard; callSite=\(callSite); allowed=false; reason=\(status.reason); requestReason=\(reason); \(hybridWatchdogContext()).")
            traceLocationEvent("Idle downgrade suppressed; initial active tracking guard is active; requestReason=\(reason) elapsed=\(formatDuration(elapsed)) entryReason=\(guardState.reason) guardReason=\(status.reason); \(hybridWatchdogContext()).")
            traceLocationEvent("Final precise-exit deferred until initial active tracking guard is satisfied.")
            if hybridTrackingWatchdogTask == nil {
                traceLocationEvent("Watchdog was missing while initial active tracking guard was active; scheduling watchdog; requestReason=\(reason); \(hybridWatchdogContext()).")
                updateHybridTrackingWatchdog(
                    for: .activeTracking,
                    reason: "idle downgrade suppressed while initial active tracking guard is active"
                )
            }
            return false
        }
        let elapsed = Date().timeIntervalSince(guardState.enteredAt)
        if guardState.firstWatchdogRecheckCompleted {
            traceLocationEvent("Idle downgrade evaluated guard; callSite=\(callSite); allowed=true; reason=first watchdog recheck completed; requestReason=\(reason); \(hybridWatchdogContext()).")
            traceLocationEvent("Idle downgrade allowed; reason=guard satisfied; guardReason=first watchdog recheck completed requestReason=\(reason) elapsed=\(formatDuration(elapsed)) entryReason=\(guardState.reason); \(hybridWatchdogContext()).")
        } else {
            traceLocationEvent("Idle downgrade evaluated guard; callSite=\(callSite); allowed=true; reason=minimum active interval elapsed; requestReason=\(reason); \(hybridWatchdogContext()).")
            traceLocationEvent("Initial active tracking guard satisfied; reason=minimum active interval elapsed; elapsed=\(formatDuration(elapsed)) entryReason=\(guardState.reason); \(hybridWatchdogContext()).")
            traceLocationEvent("Idle downgrade allowed; reason=guard satisfied; guardReason=\(status.reason) requestReason=\(reason); \(hybridWatchdogContext()).")
        }
        clearActiveTrackingEntryGuard(callSite: callSite, reason: status.reason)
        return true
    }

    private func armPostExitPreciseGuard(finalExitSample: LocationSample?, reason: String) {
        guard trackingStateMachine.policy == .hybridAutomatic else { return }
        let exitTimestamp = Date()
        postExitPreciseGuard = PostExitPreciseGuard(
            exitTimestamp: exitTimestamp,
            finalExitSample: finalExitSample,
            reason: reason
        )
        let locationDescription: String
        if let finalExitSample {
            locationDescription = String(
                format: " finalExitLocation=(%.6f, %.6f) finalExitSampleAt=%@",
                finalExitSample.latitude,
                finalExitSample.longitude,
                Self.traceDateFormatter.string(from: finalExitSample.timestamp)
            )
        } else {
            locationDescription = " finalExitLocation=unavailable"
        }
        traceLocationEvent(
            "Post-exit precise guard armed after final precise exit; exitAt=\(Self.traceDateFormatter.string(from: exitTimestamp)) reason=\(reason)\(locationDescription)."
        )
    }

    private func clearPostExitPreciseGuard(reason: String) {
        guard postExitPreciseGuard != nil else { return }
        postExitPreciseGuard = nil
        traceLocationEvent("Post-exit precise guard cleared; reason=\(reason).")
    }

    private func expirePostExitPreciseGuardIfNeeded(now: Date = Date()) {
        guard let guardState = postExitPreciseGuard else { return }
        let elapsed = now.timeIntervalSince(guardState.exitTimestamp)
        guard elapsed >= postExitPreciseGuardCooldown else { return }
        postExitPreciseGuard = nil
        traceLocationEvent("Post-exit precise guard expired after \(formatDuration(elapsed)); normal active tracking re-entry rules apply.")
    }

    private func postExitPreciseGuardAllowsActiveReentry(for sample: LocationSample) -> Bool {
        guard let guardState = postExitPreciseGuard else {
            return true
        }
        let now = Date()
        let assessment = HybridPreciseLocationSamplingRules.postExitPreciseReentryAssessment(
            sample: sample,
            exitTimestamp: guardState.exitTimestamp,
            finalExitSample: guardState.finalExitSample,
            cooldown: postExitPreciseGuardCooldown,
            activeTrackingMinimumDistanceMeters: currentAdaptiveDistanceMeters,
            stationarySpeedThreshold: trackingStateMachine.thresholds.stationarySpeedThreshold,
            minimumUsableHorizontalAccuracyMeters: trackingStateMachine.thresholds.minimumUsableHorizontalAccuracyMeters,
            now: now
        )
        let elapsed = now.timeIntervalSince(guardState.exitTimestamp)
        let distanceDescription = postExitPreciseGuardDistanceDescription(from: guardState.finalExitSample, to: sample)
        switch assessment {
        case .allowed(let reason):
            traceLocationEvent(
                "Active tracking re-entry allowed during post-exit guard; elapsed=\(formatDuration(elapsed)) \(distanceDescription) speed=\(formatSpeed(sample.speed)) accuracy=\(formatDistance(sample.horizontalAccuracy)); reason=\(reason)."
            )
            clearPostExitPreciseGuard(reason: reason)
            return true
        case .suppressed(let reason):
            traceLocationEvent(
                "Active tracking re-entry suppressed by post-exit guard; elapsed=\(formatDuration(elapsed)) \(distanceDescription) speed=\(formatSpeed(sample.speed)) accuracy=\(formatDistance(sample.horizontalAccuracy)); reason=\(reason); exitReason=\(guardState.reason)."
            )
            return false
        }
    }

    private func postExitPreciseGuardDistanceDescription(from finalExitSample: LocationSample?, to sample: LocationSample) -> String {
        guard let finalExitSample else {
            return "distanceFromFinalExit=unavailable"
        }
        return "distanceFromFinalExit=\(formatDistance(distanceMeters(from: finalExitSample, to: sample)))"
    }

    private func locationSample(from event: LocationEvent) -> LocationSample {
        LocationSample(
            latitude: event.latitude,
            longitude: event.longitude,
            horizontalAccuracy: event.horizontalAccuracy,
            course: event.course,
            speed: event.speed,
            timestamp: event.timestamp
        )
    }

    private func enqueue(location: CLLocation, context: PendingLocationContext = .coreLocationUpdate) {
        pendingLocation = location
        pendingLocationContext = context
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
            let context = pendingLocationContext
            pendingLocation = nil
            pendingLocationContext = nil
            await handle(location: location, context: context ?? .coreLocationUpdate)
        }
    }

    private func handle(location: CLLocation, context: PendingLocationContext) async {
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

        if !wasManualCapture {
            updateAdaptiveDistanceIfNeeded(
                sample: sample,
                wasCompletingFinalPreciseExit: wasCompletingFinalPreciseExit
            )
        }

        var finalPreciseExitResumedMovement = false
        if wasCompletingFinalPreciseExit {
            traceLocationEvent("Final precise exit sample received; sampleContext=\(locationContextDescription(context)).")
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
                pendingFinalPreciseExitSample = nil
                cancelFinalPreciseExit(keepActiveTracking: true)
            case .confirmsStop(let reason):
                pendingFinalPreciseExitSample = sample
                traceLocationEvent("Final precise exit sample accepted as stop confirmation (\(reason)).")
            case .rejects(let reason):
                pendingFinalPreciseExitSample = nil
                traceLocationEvent("Final precise exit sample rejected as stale/low-accuracy/jitter (\(reason)); completing final precise exit.")
                completeFinalPreciseExit()
                if isPausing {
                    isPausing = false
                }
                return
            }
        }

        traceLocationEvent("Received location sample speed=\(formatSpeed(sample.speed)) accuracy=\(formatDistance(sample.horizontalAccuracy)) manual=\(wasManualCapture) forcedStopped=\(forceStoppedCapture) trackedMode=\(trackingModeLabel()) sampleContext=\(locationContextDescription(context))")

        let previousTrackingState = trackingStateMachine.state
        var shouldRecordAutomaticTrackingSample = !wasManualCapture && (!wasCompletingFinalPreciseExit || finalPreciseExitResumedMovement)
        if shouldRecordAutomaticTrackingSample {
            expirePostExitPreciseGuardIfNeeded()
        }
        if shouldRecordAutomaticTrackingSample {
            if case .idleDetection = previousTrackingState {
                if trackingStateMachine.policy == .alwaysOffHighPrecision {
                    traceLocationEvent("Idle detection sample ignored for active tracking because Precise Location Mode is Always Off.")
                } else {
                    let qualifiesForActiveTracking = trackingStateMachine.idleDetectionSampleIndicatesMovement(sample)
                    if qualifiesForActiveTracking, !postExitPreciseGuardAllowsActiveReentry(for: sample) {
                        shouldRecordAutomaticTrackingSample = false
                    } else if qualifiesForActiveTracking {
                        traceLocationEvent("Idle detection sample qualifies for active tracking.")
                    } else {
                        traceLocationEvent("Idle detection sample does not qualify for active tracking.")
                    }
                }
            }
        }
        traceLocationEvent("Location sample usage decision; usedForTrackingState=\(shouldRecordAutomaticTrackingSample) usedForSavingDecision=true sampleContext=\(locationContextDescription(context)) previousTrackingState=\(trackingStateLabel(previousTrackingState)).")
        if shouldRecordAutomaticTrackingSample {
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
            minimumDistanceMeters: currentAdaptiveDistanceMeters,
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
                let modeBeforeSync = managerMode
                traceLocationEvent("Rejected automatic location sample will call syncTrackingMode; sampleContext=\(locationContextDescription(context)) modeBeforeSync=\(managerModeLabel(modeBeforeSync)); \(hybridWatchdogContext()).")
                syncTrackingMode()
                tracePreciseModeExitAfterSyncIfNeeded(
                    reason: "rejected automatic sample",
                    previousMode: modeBeforeSync,
                    context: context
                )
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
            if managerMode == .activeTracking {
                restartHybridTrackingWatchdog(reason: "automatic sample processed; \(context.reason)")
            } else {
                traceLocationEvent("Hybrid watchdog restart skipped after automatic sample because manager mode is \(managerModeLabel()); sampleContext=\(locationContextDescription(context)); \(hybridWatchdogContext()).")
            }
            let modeBeforeSync = managerMode
            traceLocationEvent("Accepted automatic location sample will call syncTrackingMode; sampleContext=\(locationContextDescription(context)) modeBeforeSync=\(managerModeLabel(modeBeforeSync)); \(hybridWatchdogContext()).")
            syncTrackingMode()
            tracePreciseModeExitAfterSyncIfNeeded(
                reason: "accepted automatic sample",
                previousMode: modeBeforeSync,
                context: context
            )
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
            let threshold = isPausing ? 50.0 : currentAdaptiveDistanceMeters
            return "moved \(String(format: "%.1fm", distance)) which meets the \(String(format: "%.1fm", threshold)) distance threshold"
        }

        return "did not meet the current filter rules"
    }

    private func tracePreciseModeExitIfNeeded(callSite: String, reason: String) {
        guard managerMode == .activeTracking else { return }
        if activeTrackingEntryGuard == nil,
           trackingStateMachine.policy == .hybridAutomatic {
            traceLocationEvent("Precise mode exit occurred while initial guard inactive; callSite=\(callSite); reason=\(reason); \(hybridWatchdogContext()).")
        } else if activeTrackingEntryGuard != nil {
            traceLocationEvent("Precise mode exit occurred while initial guard active; callSite=\(callSite); reason=\(reason); \(hybridWatchdogContext()).")
        }
        traceLocationEvent("Precise mode exit occurred; callSite=\(callSite); reason=\(reason); \(hybridWatchdogContext()).")
        traceLocationEvent("Exiting precise location mode; callSite=\(callSite); reason=\(reason) trackingState=\(trackingStateLabel()) elapsedSincePreciseEntry=\(preciseModeElapsedDescription()) watchdogTaskExists=\(hybridTrackingWatchdogTask != nil) activeWatchdogID=\(activeHybridWatchdogID.map(String.init) ?? "none") finalPreciseExitInProgress=\(isCompletingHybridPreciseExit) pendingFinalPreciseExitSample=\(pendingFinalPreciseExitSample != nil); \(hybridWatchdogContext()).")
    }

    private func tracePreciseModeExitAfterSyncIfNeeded(
        reason: String,
        previousMode: ManagerMode,
        context: PendingLocationContext
    ) {
        guard previousMode == .activeTracking, managerMode != .activeTracking else { return }
        traceLocationEvent("Precise location mode exited after syncTrackingMode; reason=\(reason) newMode=\(managerModeLabel()) sampleContext=\(locationContextDescription(context)) elapsedSincePreciseEntry=\(preciseModeElapsedDescription()) watchdogTaskExists=\(hybridTrackingWatchdogTask != nil) activeWatchdogID=\(activeHybridWatchdogID.map(String.init) ?? "none").")
    }

    private func locationContextDescription(_ context: PendingLocationContext) -> String {
        "source=\(context.source) cached=\(context.isCachedLocation) immediatePreciseEntry=\(context.isImmediatePreciseEntrySample) reason=\"\(context.reason)\" elapsedSincePreciseEntry=\(preciseModeElapsedDescription()) watchdogTaskExists=\(hybridTrackingWatchdogTask != nil) activeWatchdogID=\(activeHybridWatchdogID.map(String.init) ?? "none")"
    }

    private func preciseModeElapsedDescription() -> String {
        guard let preciseModeEnteredAt else {
            return "not-active-or-unknown"
        }
        return formatDuration(Date().timeIntervalSince(preciseModeEnteredAt))
    }

    private func trackingStateLabel(_ state: LocationTrackingState? = nil) -> String {
        switch state ?? trackingStateMachine.state {
        case .idleDetection:
            return "idleDetection"
        case .activeTracking:
            return "activeTracking"
        case .maybeStopped:
            return "maybeStopped"
        }
    }

    private func trackingModeLabel() -> String {
        managerModeLabel()
    }

    private func managerModeLabel(_ mode: ManagerMode? = nil) -> String {
        let mode = mode ?? managerMode
        switch mode {
        case .activeTracking:
            return "active"
        case .idleDetection:
            return "idle"
        case .stopped:
            return "stopped"
        }
    }

    private func hybridWatchdogContext() -> String {
        var parts = [
            "activeWatchdogID=\(activeHybridWatchdogID.map(String.init) ?? "none")",
            "watchdogTaskExists=\(hybridTrackingWatchdogTask != nil)",
            "managerMode=\(managerModeLabel())",
            "trackingState=\(trackingStateLabel())",
            "trackingPolicy=\(trackingStateMachine.policy.rawValue)",
            "preciseLocationMode=\(settings.preciseLocationMode.displayName)",
            "automaticTrackingEnabled=\(settings.autoAddLocations)",
            "appState=\(applicationStateLabel())",
            "finalPreciseExitInProgress=\(isCompletingHybridPreciseExit)",
            "initialActiveTrackingGuard=\(activeTrackingEntryGuardDescription())",
            "postExitGuardActive=\(postExitPreciseGuard != nil)"
        ]
        if let ignoreUntil = ignoreAutomaticLocationUpdatesUntil {
            parts.append("postExitCooldownUntil=\(Self.traceDateFormatter.string(from: ignoreUntil))")
        }
        return parts.joined(separator: " ")
    }

    private func activeTrackingEntryGuardDescription() -> String {
        guard let guardState = activeTrackingEntryGuard else {
            return "inactive"
        }
        let elapsed = Date().timeIntervalSince(guardState.enteredAt)
        let status = HybridPreciseLocationSamplingRules.initialActiveTrackingGuardStatus(
            enteredAt: guardState.enteredAt,
            firstWatchdogRecheckCompleted: guardState.firstWatchdogRecheckCompleted,
            minimumActiveInterval: minimumInitialActiveTrackingInterval
        )
        return "active(elapsed=\(formatDuration(elapsed)),firstRecheckCompleted=\(guardState.firstWatchdogRecheckCompleted),status=\(status.reason))"
    }

    private func hybridWatchdogStateDescription() -> String {
        switch hybridTrackingWatchdog.state {
        case .idle:
            return "state=idle"
        case .scheduled(let nextRecheckAt):
            return "state=scheduled nextFire=\(Self.traceDateFormatter.string(from: nextRecheckAt)) interval=\(formatDuration(hybridTrackingWatchdog.interval))"
        }
    }

    private func hybridWatchdogNextFireDescription() -> String {
        switch hybridTrackingWatchdog.state {
        case .idle:
            return "none"
        case .scheduled(let nextRecheckAt):
            return Self.traceDateFormatter.string(from: nextRecheckAt)
        }
    }

    private func applicationStateLabel() -> String {
        switch UIApplication.shared.applicationState {
        case .active:
            return "active"
        case .inactive:
            return "inactive"
        case .background:
            return "background"
        @unknown default:
            return "unknown"
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

    private func updateAdaptiveDistanceIfNeeded(
        sample: LocationSample,
        wasCompletingFinalPreciseExit: Bool
    ) {
        guard settings.autoAddLocations else { return }
        guard managerMode == .activeTracking else { return }
        guard trackingStateMachine.policy != .alwaysOffHighPrecision else { return }

        let previousDistance = currentAdaptiveDistanceMeters
        let result = adaptiveDistanceCalculator.record(sample: sample)
        if result.reason == AdaptiveLocationDistanceCalculator.transitionCooldownReason {
            traceLocationEvent("Adaptive speed-drop transition sample suppressed due to cooldown.")
        }
        if result.shouldUpdateDistanceFilter {
            updateDistanceFilter()
            onAdaptiveDistanceChanged?(result.effectiveDistanceMeters)
            traceLocationEvent(
                "Adaptive distance changed \(formatDistance(previousDistance)) -> \(formatDistance(result.effectiveDistanceMeters)); smoothedSpeed=\(formatSpeed(adaptiveDistanceCalculator.state.smoothedSpeedMetersPerSecond ?? -1)); detail=\(settings.locationDetailMode.displayName); reason=\(result.reason)."
            )
        }

        guard result.shouldRequestTransitionSample else { return }
        guard !wasCompletingFinalPreciseExit,
              !isCompletingHybridPreciseExit
        else {
            traceLocationEvent("Adaptive speed-drop transition sample suppressed during final precise exit.")
            return
        }
        if case .maybeStopped = trackingStateMachine.state {
            traceLocationEvent("Adaptive speed-drop transition sample suppressed during stop detection.")
            return
        }
        requestAutomaticLocationSample(
            reason: "Adaptive distance detected sustained highway-to-town speed drop; requesting one automatic transition sample.",
            useCachedLocationFirst: false
        )
    }

    private func formatDistance(_ value: Double) -> String {
        guard value.isFinite else { return "unknown" }
        return String(format: "%.1fm", value)
    }

    private func formatSpeed(_ value: Double) -> String {
        guard value.isFinite else { return "unknown" }
        return String(format: "%.2fm/s", value)
    }

    private func formatDuration(_ value: TimeInterval) -> String {
        guard value.isFinite else { return "unknown" }
        return String(format: "%.1fs", max(0, value))
    }

    private func distanceMeters(from lhs: LocationSample, to rhs: LocationSample) -> Double {
        let radius = 6_371_000.0
        let phi1 = lhs.latitude * .pi / 180
        let phi2 = rhs.latitude * .pi / 180
        let deltaPhi = (rhs.latitude - lhs.latitude) * .pi / 180
        let deltaLambda = (rhs.longitude - lhs.longitude) * .pi / 180
        let a = sin(deltaPhi / 2) * sin(deltaPhi / 2)
            + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return radius * c
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
