// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.

import CoreLocation
import Foundation
import UIKit

#if canImport(TravelsCore)
import TravelsCore
#endif

@MainActor
final class LocationTrackingService: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private weak var store: TravelsStore?
    private var settings = AppSettings()
    private var latestAcceptedEvent: LocationEvent?
    private var isConfigured = false
    private var pendingAlwaysAuthorization = false
    private var didScheduleAlwaysAuthorizationUpgrade = false
    private var isPausing = false
    private var pendingManualCapture = false
    private var pendingForcedStoppedCapture = false
    private var pendingLocation: CLLocation?
    private var locationProcessingTask: Task<Void, Never>?

    var onStatusMessage: ((String) -> Void)?
    var onTrackedEvent: (() -> Void)?
    var onManualTrackedEvent: ((Int64, Date) -> Void)?
    var onAuthorizationStateChanged: ((String?) -> Void)?

    var authorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func configure(store: TravelsStore, settings: AppSettings, latestEvent: LocationEvent?) {
        self.store = store
        self.settings = settings
        self.latestAcceptedEvent = latestEvent
        locationManager.allowsBackgroundLocationUpdates = settings.backgroundLocationEnabled
        locationManager.showsBackgroundLocationIndicator = settings.backgroundLocationEnabled
        locationManager.activityType = .other
        UIDevice.current.isBatteryMonitoringEnabled = true
        updateDistanceFilter()
        updatePauseBehavior()
        if !isConfigured {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(batteryStateDidChange(_:)),
                name: UIDevice.batteryStateDidChangeNotification,
                object: nil
            )
            isConfigured = true
        }
        refreshAuthorization()
    }

    func update(settings: AppSettings) {
        self.settings = settings
        locationManager.allowsBackgroundLocationUpdates = settings.backgroundLocationEnabled
        locationManager.showsBackgroundLocationIndicator = settings.backgroundLocationEnabled
        updateDistanceFilter()
        updatePauseBehavior()
        refreshAuthorization()
    }

    func stop() {
        pendingManualCapture = false
        pendingForcedStoppedCapture = false
        isPausing = false
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.stopUpdatingLocation()
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
            locationManager.stopMonitoringSignificantLocationChanges()
            locationManager.stopUpdatingLocation()
            onAuthorizationStateChanged?(nil)
            return
        }

        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            pendingAlwaysAuthorization = false
            didScheduleAlwaysAuthorizationUpgrade = false
            onAuthorizationStateChanged?(nil)
            startTrackingIfNeeded()
            locationManager.startUpdatingLocation()
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
                startTrackingIfNeeded()
                locationManager.startUpdatingLocation()
            }
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
        let shouldPauseAutomatically = UIDevice.current.batteryState != .charging && UIDevice.current.batteryState != .full
        locationManager.pausesLocationUpdatesAutomatically = shouldPauseAutomatically
        if shouldPauseAutomatically {
            locationManager.allowDeferredLocationUpdates(
                untilTraveled: CLLocationDistance(kCLLocationAccuracyKilometer),
                timeout: CLTimeIntervalMax
            )
        } else {
            locationManager.disallowDeferredLocationUpdates()
        }
    }

    private func startTrackingIfNeeded() {
        guard settings.autoAddLocations else { return }
        locationManager.startMonitoringSignificantLocationChanges()
    }

    private func currentDistanceFilter() -> CLLocationDistance {
        switch UIDevice.current.batteryState {
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
        if settings.autoAddLocations {
            locationManager.requestLocation()
        }
    }

    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        isPausing = false
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError, clError.code == .locationUnknown {
            return
        }
        onStatusMessage?(error.localizedDescription)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            return
        }
        guard settings.autoAddLocations || pendingManualCapture else {
            return
        }
        enqueue(location: location)
    }

    @objc private func batteryStateDidChange(_ notification: Notification) {
        updateDistanceFilter()
        updatePauseBehavior()
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

        let decision = LocationFiltering.decision(
            candidate: sample,
            previous: latestAcceptedEvent,
            force: forceCapture,
            isPausing: isPausing,
            minimumDistanceMeters: Double(settings.poweredUpdateDistanceMeters),
            pausedMinimumDistanceMeters: 50
        )

        guard decision != .reject else {
            return
        }

        var event = LocationFiltering.event(from: sample, source: .locationServices)
        if decision == .acceptAndReplacePrevious {
            event.geolocationID = latestAcceptedEvent?.geolocationID
        }
        do {
            let eventID = try await save(
                event: event,
                replacingEventID: decision == .acceptAndReplacePrevious ? latestAcceptedEvent?.id : nil
            )
            if wasManualCapture, eventID > 0 {
                onManualTrackedEvent?(eventID, event.timestamp)
            }
        } catch {
            onStatusMessage?(error.localizedDescription)
        }

        if isPausing {
            isPausing = false
        }
    }

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
