// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.
import CoreLocation
import Foundation

#if canImport(TravelsCore)
import TravelsCore
#endif

actor ReverseGeocodingService {
    static let shared = ReverseGeocodingService()

    private let geocoder = CLGeocoder()
    private let minimumSpacing: TimeInterval = 60
    private var lastLookupCompletedAt: Date?
    private var cache: [CacheKey: Geolocation] = [:]

    func geolocation(for location: CLLocation, store: TravelsStore? = nil) async -> Geolocation? {
        await lookup(for: location, store: store).geolocation
    }

    func lookup(for location: CLLocation, store: TravelsStore? = nil) async -> ReverseGeocodingLookupResult {
        let cacheKey = CacheKey(location: location)
        if let cached = cache[cacheKey] {
            return ReverseGeocodingLookupResult(
                geolocation: cached,
                source: .sessionCache,
                waitedSeconds: 0,
                summary: "Resolved from in-memory cache"
            )
        }

        if let store, let saved = try? store.geolocation(near: location.coordinate.latitude, longitude: location.coordinate.longitude) {
            cache[cacheKey] = saved
            return ReverseGeocodingLookupResult(
                geolocation: saved,
                source: .storeCache,
                waitedSeconds: 0,
                summary: "Resolved from saved geolocation cache"
            )
        }

        let waitedSeconds = await waitIfNeeded()

        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else {
                return ReverseGeocodingLookupResult(
                    geolocation: nil,
                    source: .apple,
                    waitedSeconds: waitedSeconds,
                    summary: "Apple returned no placemark"
                )
            }
            let geolocation = Geolocation(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                radius: max(location.horizontalAccuracy, 0),
                identifier: placemark.name ?? "",
                horizontalAccuracy: location.horizontalAccuracy,
                verticalAccuracy: location.verticalAccuracy,
                altitude: location.altitude,
                timestamp: location.timestamp,
                timeZoneIdentifier: placemark.timeZone?.identifier ?? "",
                name: placemark.name ?? "",
                subThoroughfare: placemark.subThoroughfare ?? "",
                thoroughfare: placemark.thoroughfare ?? "",
                subLocality: placemark.subLocality ?? "",
                locality: placemark.locality ?? "",
                subAdministrativeArea: placemark.subAdministrativeArea ?? "",
                administrativeArea: placemark.administrativeArea ?? "",
                postalCode: placemark.postalCode ?? "",
                isoCountryCode: placemark.isoCountryCode ?? "",
                country: placemark.country ?? "",
                inlandWater: placemark.inlandWater ?? "",
                ocean: placemark.ocean ?? "",
                areasOfInterest: placemark.areasOfInterest ?? []
            )
            cache[cacheKey] = geolocation
            lastLookupCompletedAt = Date()
            if let store, let geolocationID = try? store.saveGeolocation(geolocation) {
                var persisted = geolocation
                persisted.id = geolocationID
                cache[cacheKey] = persisted
                return ReverseGeocodingLookupResult(
                    geolocation: persisted,
                    source: .apple,
                    waitedSeconds: waitedSeconds,
                    summary: "Resolved via Apple and saved locally"
                )
            }
            return ReverseGeocodingLookupResult(
                geolocation: geolocation,
                source: .apple,
                waitedSeconds: waitedSeconds,
                summary: "Resolved via Apple"
            )
        } catch {
            lastLookupCompletedAt = Date()
            return ReverseGeocodingLookupResult(
                geolocation: nil,
                source: .apple,
                waitedSeconds: waitedSeconds,
                summary: "Apple geocoder failed: \(error.localizedDescription)",
                errorDescription: error.localizedDescription
            )
        }
    }

    private func waitIfNeeded() async -> TimeInterval {
        guard let lastLookupCompletedAt else { return 0 }
        let elapsed = Date().timeIntervalSince(lastLookupCompletedAt)
        let remaining = minimumSpacing - elapsed
        guard remaining > 0 else { return 0 }
        try? await Task.sleep(for: .seconds(remaining))
        return remaining
    }
}

struct ReverseGeocodingLookupResult {
    enum Source: String, Sendable {
        case sessionCache
        case storeCache
        case apple
    }

    let geolocation: Geolocation?
    let source: Source
    let waitedSeconds: TimeInterval
    let summary: String
    let errorDescription: String?

    init(
        geolocation: Geolocation?,
        source: Source,
        waitedSeconds: TimeInterval,
        summary: String,
        errorDescription: String? = nil
    ) {
        self.geolocation = geolocation
        self.source = source
        self.waitedSeconds = waitedSeconds
        self.summary = summary
        self.errorDescription = errorDescription
    }
}

private struct CacheKey: Hashable {
    let latitude: Int
    let longitude: Int

    init(location: CLLocation) {
        latitude = Int((location.coordinate.latitude * 100_000).rounded())
        longitude = Int((location.coordinate.longitude * 100_000).rounded())
    }
}
