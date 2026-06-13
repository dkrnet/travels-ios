// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.

import Foundation

public enum HybridPreciseLocationSamplingRules {
    public static func shouldRequestImmediateAutomaticSample(
        isEnteringActiveTracking: Bool,
        automaticLocationTrackingEnabled: Bool,
        hasLocationAuthorization: Bool,
        isCompletingFinalPreciseExit: Bool
    ) -> Bool {
        isEnteringActiveTracking
            && automaticLocationTrackingEnabled
            && hasLocationAuthorization
            && !isCompletingFinalPreciseExit
    }

    public static func shouldStartBoundedFinalPreciseExit(
        currentManagerIsActive: Bool,
        desiredIdleDetection: Bool,
        isHybridPolicy: Bool,
        automaticLocationTrackingEnabled: Bool,
        hasLocationAuthorization: Bool,
        isCompletingFinalPreciseExit: Bool
    ) -> Bool {
        currentManagerIsActive
            && desiredIdleDetection
            && isHybridPolicy
            && automaticLocationTrackingEnabled
            && hasLocationAuthorization
            && !isCompletingFinalPreciseExit
    }

    public static func sampleIndicatesMovementResumed(
        sample: LocationSample,
        latestAcceptedEvent: LocationEvent?,
        stationarySpeedThreshold: Double,
        stationaryRadiusMeters: Double,
        minimumUsableHorizontalAccuracyMeters: Double
    ) -> Bool {
        if sample.speed.isFinite, sample.speed >= stationarySpeedThreshold {
            return true
        }

        guard sample.horizontalAccuracy.isFinite, sample.horizontalAccuracy >= 0 else {
            return false
        }

        guard sample.horizontalAccuracy <= minimumUsableHorizontalAccuracyMeters else {
            return false
        }

        guard let latestAcceptedEvent else {
            return false
        }

        let distance = haversineMeters(
            fromLatitude: latestAcceptedEvent.latitude,
            longitude: latestAcceptedEvent.longitude,
            toLatitude: sample.latitude,
            longitude: sample.longitude
        )
        return distance >= stationaryRadiusMeters
    }

    private static func haversineMeters(
        fromLatitude lat1: Double,
        longitude lon1: Double,
        toLatitude lat2: Double,
        longitude lon2: Double
    ) -> Double {
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
