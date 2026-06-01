// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public struct LocationSample: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var horizontalAccuracy: Double
    public var course: Double
    public var speed: Double
    public var timestamp: Date

    public init(latitude: Double, longitude: Double, horizontalAccuracy: Double, course: Double = -1, speed: Double = -1, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.course = course
        self.speed = speed
        self.timestamp = timestamp
    }
}

public enum LocationFilterDecision: Equatable, Sendable {
    case accept
    case acceptAndReplacePrevious
    case reject
}

public enum LocationFiltering {
    public static func decision(
        candidate: LocationSample,
        previous: LocationEvent?,
        force: Bool = false,
        isPausing: Bool = false,
        minimumDistanceMeters: Double = 100,
        pausedMinimumDistanceMeters: Double = 50,
        maximumHorizontalAccuracyMeters: Double = 100,
        improvementWindowSeconds: TimeInterval = 300
    ) -> LocationFilterDecision {
        guard let previous else {
            return .accept
        }
        if force {
            return .accept
        }

        let elapsed = candidate.timestamp.timeIntervalSince(previous.timestamp)
        if elapsed < 0 {
            return .reject
        }

        let distance = haversineMeters(
            fromLatitude: previous.latitude,
            longitude: previous.longitude,
            toLatitude: candidate.latitude,
            longitude: candidate.longitude
        )

        if distance <= previous.horizontalAccuracy {
            if elapsed < improvementWindowSeconds && candidate.horizontalAccuracy < previous.horizontalAccuracy {
                return .acceptAndReplacePrevious
            }
            return .reject
        }

        if distance <= candidate.horizontalAccuracy {
            return .reject
        }

        let distanceThreshold = isPausing ? pausedMinimumDistanceMeters : minimumDistanceMeters
        let distanceOK = distance >= distanceThreshold
        let accuracyOK = candidate.horizontalAccuracy <= maximumHorizontalAccuracyMeters
        return distanceOK && accuracyOK ? .accept : .reject
    }

    public static func event(from sample: LocationSample, source: EventSource, geolocationID: Int64? = nil) -> LocationEvent {
        LocationEvent(
            latitude: sample.latitude,
            longitude: sample.longitude,
            horizontalAccuracy: sample.horizontalAccuracy,
            course: sample.course,
            speed: sample.speed,
            timestamp: sample.timestamp,
            localizedDate: TravelsDateTools.localizedDayString(for: sample.timestamp, timeZoneIdentifier: nil),
            source: source,
            geolocationID: geolocationID
        )
    }

    private static func haversineMeters(fromLatitude lat1: Double, longitude lon1: Double, toLatitude lat2: Double, longitude lon2: Double) -> Double {
        let radius = 6_371_000.0
        let phi1 = lat1 * .pi / 180
        let phi2 = lat2 * .pi / 180
        let deltaPhi = (lat2 - lat1) * .pi / 180
        let deltaLambda = (lon2 - lon1) * .pi / 180
        let a = sin(deltaPhi / 2) * sin(deltaPhi / 2)
            + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return radius * c
    }
}
