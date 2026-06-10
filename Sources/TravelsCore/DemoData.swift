// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public enum DemoData {
    public static let seedVersion = "gpx-demo-metadata-v2"

    private static let resourceNames = [
        "demo-2017-06-30",
        "demo-2018-01-05",
        "demo-2018-07-06"
    ]

    public static func seed(into store: TravelsStore, anchoredTo referenceDate: Date, bundle: Bundle = .main) throws {
        let urls = try demoTrackURLs(bundle: bundle)
        try seed(into: store, anchoredTo: referenceDate, trackURLs: urls)
    }

    public static func seed(into store: TravelsStore, anchoredTo referenceDate: Date, trackURLs: [URL]) throws {
        let points = try trackPoints(anchoredTo: referenceDate, trackURLs: trackURLs)
        for point in points {
            let geolocationID = try point.geolocation.map { try store.saveGeolocation($0) }
            let event = LocationEvent(
                latitude: point.event.latitude,
                longitude: point.event.longitude,
                horizontalAccuracy: point.event.horizontalAccuracy,
                verticalAccuracy: point.event.verticalAccuracy,
                altitude: point.event.altitude,
                course: point.event.course,
                speed: point.event.speed,
                timestamp: point.event.timestamp,
                localizedDate: point.event.localizedDate,
                source: .simulated,
                geolocationID: geolocationID
            )
            _ = try store.saveEvent(event, isDemo: true)
        }
    }

    public static func trackPoints(anchoredTo referenceDate: Date, bundle: Bundle = .main) throws -> [GPXTrackPoint] {
        let urls = try demoTrackURLs(bundle: bundle)
        return try trackPoints(anchoredTo: referenceDate, trackURLs: urls)
    }

    public static func trackPoints(anchoredTo referenceDate: Date, trackURLs: [URL]) throws -> [GPXTrackPoint] {
        let calendar = Calendar.current
        let launchDay = calendar.startOfDay(for: referenceDate)
        let targetOffsets = [-3, -2, -1]
        var points: [GPXTrackPoint] = []
        for (index, trackURL) in trackURLs.prefix(targetOffsets.count).enumerated() {
            let imported = try GPXImporter.parse(url: trackURL)
            let eventsWithMotion = synthesizeMotionMetadata(for: imported.trackPoints.map(\.event))
            guard let firstTimestamp = eventsWithMotion.first?.timestamp else { continue }
            let sourceDay = calendar.startOfDay(for: firstTimestamp)
            let targetDay = calendar.date(byAdding: .day, value: targetOffsets[index], to: launchDay) ?? launchDay
            let shift = targetDay.timeIntervalSince(sourceDay)

            for (importedTrackPoint, importedEvent) in zip(imported.trackPoints, eventsWithMotion) {
                let timestamp = importedEvent.timestamp.addingTimeInterval(shift)
                let event = LocationEvent(
                    latitude: importedEvent.latitude,
                    longitude: importedEvent.longitude,
                    horizontalAccuracy: importedEvent.horizontalAccuracy,
                    verticalAccuracy: importedEvent.verticalAccuracy,
                    altitude: importedEvent.altitude,
                    course: importedEvent.course,
                    speed: importedEvent.speed,
                    timestamp: timestamp,
                    localizedDate: TravelsDateTools.localizedDayString(
                        for: timestamp,
                        timeZoneIdentifier: importedTrackPoint.geolocation?.timeZoneIdentifier
                    ),
                    source: .simulated
                )
                let geolocation = importedTrackPoint.geolocation.map { shiftedGeolocation($0, timestamp: timestamp) }
                points.append(GPXTrackPoint(event: event, geolocation: geolocation))
            }
        }
        return points
    }

    private static func synthesizeMotionMetadata(for events: [LocationEvent]) -> [LocationEvent] {
        guard !events.isEmpty else { return [] }
        var synthesized = events
        for index in synthesized.indices {
            let previous = index > 0 ? synthesized[index - 1] : nil
            let next = index < synthesized.count - 1 ? synthesized[index + 1] : nil
            let motion = motionMetadata(previous: previous, current: synthesized[index], next: next)
            synthesized[index].course = motion.course
            synthesized[index].speed = motion.speed
        }
        return synthesized
    }

    private static func motionMetadata(previous: LocationEvent?, current: LocationEvent, next: LocationEvent?) -> (course: Double, speed: Double) {
        if let next {
            let seconds = max(next.timestamp.timeIntervalSince(current.timestamp), 1)
            let distance = distanceMeters(from: current, to: next)
            let speed = max(distance / seconds, 0.1)
            return (bearingDegrees(from: current, to: next), speed)
        }
        if let previous {
            let seconds = max(current.timestamp.timeIntervalSince(previous.timestamp), 1)
            let distance = distanceMeters(from: previous, to: current)
            let speed = max(distance / seconds, 0.1)
            return (bearingDegrees(from: previous, to: current), speed)
        }
        return (course: 0, speed: 0.1)
    }

    private static func shiftedGeolocation(_ geolocation: Geolocation, timestamp: Date) -> Geolocation {
        var shifted = geolocation
        shifted.timestamp = timestamp
        return shifted
    }

    private static func distanceMeters(from lhs: LocationEvent, to rhs: LocationEvent) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = lhs.latitude * .pi / 180
        let lat2 = rhs.latitude * .pi / 180
        let deltaLat = (rhs.latitude - lhs.latitude) * .pi / 180
        let deltaLon = (rhs.longitude - lhs.longitude) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
        return earthRadius * c
    }

    private static func bearingDegrees(from lhs: LocationEvent, to rhs: LocationEvent) -> Double {
        let lat1 = lhs.latitude * .pi / 180
        let lat2 = rhs.latitude * .pi / 180
        let deltaLon = (rhs.longitude - lhs.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let bearing = atan2(y, x) * 180 / .pi
        return bearing < 0 ? bearing + 360 : bearing
    }

    private static func demoTrackURLs(bundle: Bundle) throws -> [URL] {
        try resourceNames.map { name in
            guard let url = bundle.url(forResource: name, withExtension: "gpx") else {
                throw TravelsError.invalidGPX("Missing bundled demo track: \(name).gpx")
            }
            return url
        }
    }
}
