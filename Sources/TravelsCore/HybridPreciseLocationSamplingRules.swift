// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.

import Foundation

public enum FinalPreciseExitSampleAssessment: Equatable, Sendable {
    case confirmsStop(reason: String)
    case rejects(reason: String)
    case movementResumed(reason: String)

    public var indicatesMovementResumed: Bool {
        if case .movementResumed = self {
            return true
        }
        return false
    }
}

public enum PostExitPreciseReentryAssessment: Equatable, Sendable {
    case allowed(reason: String)
    case suppressed(reason: String)

    public var allowsReentry: Bool {
        if case .allowed = self {
            return true
        }
        return false
    }
}

public struct InitialActiveTrackingGuardStatus: Equatable, Sendable {
    public var isActive: Bool
    public var reason: String

    public init(isActive: Bool, reason: String) {
        self.isActive = isActive
        self.reason = reason
    }
}

public enum HybridPreciseLocationSamplingRules {
    private static let finalExitMaximumSampleAge: TimeInterval = 30

    public static func initialActiveTrackingGuardStatus(
        enteredAt: Date?,
        firstWatchdogRecheckCompleted: Bool,
        minimumActiveInterval: TimeInterval,
        now: Date = Date()
    ) -> InitialActiveTrackingGuardStatus {
        guard let enteredAt else {
            return InitialActiveTrackingGuardStatus(isActive: false, reason: "initial active tracking guard is not armed")
        }

        if firstWatchdogRecheckCompleted {
            return InitialActiveTrackingGuardStatus(isActive: false, reason: "first watchdog recheck completed")
        }

        let elapsed = now.timeIntervalSince(enteredAt)
        guard elapsed < minimumActiveInterval else {
            return InitialActiveTrackingGuardStatus(isActive: false, reason: "minimum active interval elapsed")
        }

        return InitialActiveTrackingGuardStatus(isActive: true, reason: "waiting for first watchdog recheck or minimum active interval")
    }

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
        finalPreciseExitSampleAssessment(
            sample: sample,
            latestAcceptedEvent: latestAcceptedEvent,
            stationarySpeedThreshold: stationarySpeedThreshold,
            stationaryRadiusMeters: stationaryRadiusMeters,
            minimumUsableHorizontalAccuracyMeters: minimumUsableHorizontalAccuracyMeters,
            now: sample.timestamp.addingTimeInterval(1)
        ).indicatesMovementResumed
    }

    public static func finalPreciseExitSampleAssessment(
        sample: LocationSample,
        latestAcceptedEvent: LocationEvent?,
        stationarySpeedThreshold: Double,
        stationaryRadiusMeters: Double,
        minimumUsableHorizontalAccuracyMeters: Double,
        now: Date = Date()
    ) -> FinalPreciseExitSampleAssessment {
        guard sample.timestamp <= now.addingTimeInterval(1) else {
            return .rejects(reason: "sample timestamp is in the future")
        }

        if now.timeIntervalSince(sample.timestamp) > finalExitMaximumSampleAge {
            return .rejects(reason: "sample is stale")
        }

        guard sample.horizontalAccuracy.isFinite, sample.horizontalAccuracy >= 0 else {
            return .rejects(reason: "horizontal accuracy is unavailable")
        }

        guard sample.horizontalAccuracy <= minimumUsableHorizontalAccuracyMeters else {
            return .rejects(reason: "horizontal accuracy is too low")
        }

        let resumeSpeedThreshold = max(stationarySpeedThreshold * 2, stationarySpeedThreshold + 0.8)
        if sample.speed.isFinite, sample.speed >= resumeSpeedThreshold {
            return .movementResumed(reason: "speed is meaningfully above the resume threshold")
        }

        guard let latestAcceptedEvent else {
            return .confirmsStop(reason: "no previous event is available for distance comparison")
        }

        guard sample.timestamp > latestAcceptedEvent.timestamp else {
            return .rejects(reason: "sample is not newer than the stationary reference")
        }

        let distance = haversineMeters(
            fromLatitude: latestAcceptedEvent.latitude,
            longitude: latestAcceptedEvent.longitude,
            toLatitude: sample.latitude,
            longitude: sample.longitude
        )
        let referenceAccuracy = latestAcceptedEvent.horizontalAccuracy.isFinite && latestAcceptedEvent.horizontalAccuracy >= 0
            ? latestAcceptedEvent.horizontalAccuracy
            : 0
        let materialMovementThreshold = stationaryRadiusMeters + max(sample.horizontalAccuracy, referenceAccuracy, 10)
        if distance >= materialMovementThreshold {
            return .movementResumed(reason: "distance from the stationary reference is material")
        }

        return .confirmsStop(reason: "sample remains within the stationary reference area")
    }

    public static func postExitPreciseReentryAssessment(
        sample: LocationSample,
        exitTimestamp: Date,
        finalExitSample: LocationSample?,
        cooldown: TimeInterval,
        activeTrackingMinimumDistanceMeters: Double,
        stationarySpeedThreshold: Double,
        minimumUsableHorizontalAccuracyMeters: Double,
        now: Date = Date()
    ) -> PostExitPreciseReentryAssessment {
        let elapsed = now.timeIntervalSince(exitTimestamp)
        if elapsed >= cooldown {
            return .allowed(reason: "post-exit guard cooldown expired")
        }

        guard sample.horizontalAccuracy.isFinite, sample.horizontalAccuracy >= 0 else {
            return .suppressed(reason: "horizontal accuracy is unavailable")
        }

        guard sample.horizontalAccuracy <= minimumUsableHorizontalAccuracyMeters else {
            return .suppressed(reason: "horizontal accuracy is too low")
        }

        let referenceTimestamp = finalExitSample?.timestamp ?? exitTimestamp
        guard sample.timestamp > referenceTimestamp else {
            return .suppressed(reason: "sample is not newer than the final-exit reference")
        }

        let resumeSpeedThreshold = max(stationarySpeedThreshold * 2, stationarySpeedThreshold + 0.8)
        if sample.speed.isFinite, sample.speed >= resumeSpeedThreshold {
            return .allowed(reason: "speed is meaningfully above the resume threshold")
        }

        guard let finalExitSample else {
            return .suppressed(reason: "no final-exit location is available for distance comparison")
        }

        let distance = haversineMeters(
            fromLatitude: finalExitSample.latitude,
            longitude: finalExitSample.longitude,
            toLatitude: sample.latitude,
            longitude: sample.longitude
        )
        let referenceAccuracy = finalExitSample.horizontalAccuracy.isFinite && finalExitSample.horizontalAccuracy >= 0
            ? finalExitSample.horizontalAccuracy
            : 0
        let materialMovementThreshold = max(
            activeTrackingMinimumDistanceMeters,
            sample.horizontalAccuracy * 2,
            referenceAccuracy * 2,
            150
        )
        if distance >= materialMovementThreshold {
            return .allowed(reason: "distance from final-exit location is material")
        }

        return .suppressed(reason: "sample did not prove movement resumed")
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
