// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.

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
    public static let stoppedNonDuplicateRadiusMeters = 20.0
    public static let recentStoppedDuplicateWindowSeconds: TimeInterval = 5 * 60

    public static func shouldForceNonDuplicateCapture(
        candidate: LocationSample,
        previous: LocationEvent?,
        duplicateRadiusMeters: Double
    ) -> Bool {
        guard let previous else {
            return true
        }
        let radius = max(0, duplicateRadiusMeters)
        return haversineMeters(
            fromLatitude: previous.latitude,
            longitude: previous.longitude,
            toLatitude: candidate.latitude,
            longitude: candidate.longitude
        ) > radius
    }

    public static func shouldMarkPreviousEventStoppedForRecentDuplicate(
        candidate: LocationSample,
        previous: LocationEvent?,
        duplicateRadiusMeters: Double,
        recencyWindowSeconds: TimeInterval = recentStoppedDuplicateWindowSeconds
    ) -> Bool {
        guard let previous else { return false }
        let elapsed = candidate.timestamp.timeIntervalSince(previous.timestamp)
        guard elapsed >= 0, elapsed < max(0, recencyWindowSeconds) else { return false }
        return !shouldForceNonDuplicateCapture(
            candidate: candidate,
            previous: previous,
            duplicateRadiusMeters: duplicateRadiusMeters
        )
    }

    public static func shouldMarkPreviousEventStoppedForConfirmedAutomaticStop(
        candidate: LocationSample,
        previous: LocationEvent?,
        duplicateRadiusMeters: Double,
        stationaryAnchorTimestamp: Date,
        associationWindowSeconds: TimeInterval = recentStoppedDuplicateWindowSeconds
    ) -> Bool {
        guard let previous else { return false }
        guard candidate.timestamp >= stationaryAnchorTimestamp,
              previous.timestamp <= candidate.timestamp
        else {
            return false
        }
        // REGRESSION GUARD: automatic stop confirmation intentionally takes about five minutes.
        // Associate the arrival event with the start of that stationary episode so the detection
        // delay itself does not make the event too old to receive the stopped override.
        let earliestAssociatedTimestamp = stationaryAnchorTimestamp.addingTimeInterval(
            -max(0, associationWindowSeconds)
        )
        guard previous.timestamp >= earliestAssociatedTimestamp else { return false }
        return !shouldForceNonDuplicateCapture(
            candidate: candidate,
            previous: previous,
            duplicateRadiusMeters: duplicateRadiusMeters
        )
    }

    public static func replacementMovementStateOverride(
        requested: MovementStateOverride?,
        previous: LocationEvent?
    ) -> MovementStateOverride? {
        requested ?? previous?.movementStateOverride
    }

    public static func decision(
        candidate: LocationSample,
        previous: LocationEvent?,
        force: Bool = false,
        isPausing: Bool = false,
        minimumDistanceMeters: Double = 100,
        pausedMinimumDistanceMeters: Double = 50,
        maximumHorizontalAccuracyMeters: Double = 100,
        improvementWindowSeconds: TimeInterval = 300,
        stationarySpeedThreshold: Double = LocationTrackingThresholds().stationarySpeedThreshold
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
            let isMoreAccurate = candidate.horizontalAccuracy < previous.horizontalAccuracy
            let candidateSpeedUnavailable = !candidate.speed.isFinite || candidate.speed < 0
            let previousSpeedUnavailable = !previous.speed.isFinite || previous.speed < 0
            let isAtLeastAsAccurateAndSlower = candidate.horizontalAccuracy <= previous.horizontalAccuracy
                && (
                    (candidate.speed >= 0 && previous.speed >= 0 && candidate.speed < previous.speed)
                    || (candidateSpeedUnavailable && previous.speed <= 0)
                    || (previousSpeedUnavailable && candidate.speed <= 0)
                )
            let candidateIsStopped = candidate.speed.isFinite
                && candidate.speed >= 0
                && candidate.speed <= stationarySpeedThreshold
            let previousIsMoving = previous.speed.isFinite
                && previous.speed > stationarySpeedThreshold
            let candidateAccuracyIsUsable = candidate.horizontalAccuracy.isFinite
                && candidate.horizontalAccuracy >= 0
                && candidate.horizontalAccuracy <= maximumHorizontalAccuracyMeters
            // REGRESSION GUARD: A usable stopped fix can be the destination even when
            // it is slightly less accurate, so prefer it over the nearby moving fix.
            let stoppedCandidateReplacesMovingEvent = candidateIsStopped
                && previousIsMoving
                && candidateAccuracyIsUsable
            if elapsed < improvementWindowSeconds
                && (isMoreAccurate || isAtLeastAsAccurateAndSlower || stoppedCandidateReplacesMovingEvent) {
                return .acceptAndReplacePrevious
            }
            return .reject
        }

        if distance <= candidate.horizontalAccuracy {
            return .reject
        }

        let threshold = isPausing ? pausedMinimumDistanceMeters : minimumDistanceMeters
        let distanceOK = distance >= threshold
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
