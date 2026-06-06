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

    var onStatusMessage: ((String) -> Void)?
    var onTrackedEvent: (() -> Void)?

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
        UIDevice.current.isBatteryMonitoringEnabled = true
        updateDistanceFilter()
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
        refreshAuthorization()
    }

    func stop() {
        locationManager.stopUpdatingLocation()
    }

    private func refreshAuthorization() {
        guard settings.autoAddLocations else {
            locationManager.stopUpdatingLocation()
            return
        }

        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            pendingAlwaysAuthorization = false
            didScheduleAlwaysAuthorizationUpgrade = false
            locationManager.startUpdatingLocation()
        case .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
            if settings.backgroundLocationEnabled {
                pendingAlwaysAuthorization = true
                scheduleAlwaysAuthorizationUpgrade()
            } else {
                pendingAlwaysAuthorization = false
                didScheduleAlwaysAuthorizationUpgrade = false
            }
        case .notDetermined:
            pendingAlwaysAuthorization = settings.backgroundLocationEnabled
            didScheduleAlwaysAuthorizationUpgrade = false
            if settings.backgroundLocationEnabled {
                locationManager.requestAlwaysAuthorization()
            } else {
                locationManager.requestWhenInUseAuthorization()
            }
        case .denied, .restricted:
            pendingAlwaysAuthorization = false
            didScheduleAlwaysAuthorizationUpgrade = false
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

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError, clError.code == .locationUnknown {
            return
        }
        onStatusMessage?(error.localizedDescription)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard settings.autoAddLocations, let location = locations.last else {
            return
        }
        Task {
            await handle(location: location)
        }
    }

    @objc private func batteryStateDidChange(_ notification: Notification) {
        updateDistanceFilter()
    }

    private func handle(location: CLLocation) async {
        let sample = LocationSample(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            course: location.course,
            speed: location.speed,
            timestamp: location.timestamp
        )

        let decision = LocationFiltering.decision(
            candidate: sample,
            previous: latestAcceptedEvent,
            minimumDistanceMeters: Double(settings.poweredUpdateDistanceMeters),
            pausedMinimumDistanceMeters: Double(settings.batteryUpdateDistanceMeters)
        )

        guard decision != .reject else {
            return
        }

        let event = LocationFiltering.event(from: sample, source: .locationServices)
        do {
            try save(event: event)
        } catch {
            onStatusMessage?(error.localizedDescription)
        }
    }

    private func save(event: LocationEvent) throws {
        guard let store else { return }
        _ = try store.saveEvent(event)
        latestAcceptedEvent = event
        onTrackedEvent?()
    }
}
