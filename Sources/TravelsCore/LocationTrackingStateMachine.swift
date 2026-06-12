// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.

import Foundation

public enum LocationTrackingPolicy: String, Codable, CaseIterable, Sendable {
    case hybridAutomatic
    case alwaysOnHighPrecision
}

public struct LocationTrackingThresholds: Equatable, Sendable {
    public var stationaryDuration: TimeInterval
    public var stationaryRadiusMeters: Double
    public var stationarySpeedThreshold: Double
    public var minimumUsableHorizontalAccuracyMeters: Double

    public init(
        stationaryDuration: TimeInterval = 5 * 60,
        stationaryRadiusMeters: Double = 50,
        stationarySpeedThreshold: Double = 0.7,
        minimumUsableHorizontalAccuracyMeters: Double = 100
    ) {
        self.stationaryDuration = stationaryDuration
        self.stationaryRadiusMeters = stationaryRadiusMeters
        self.stationarySpeedThreshold = stationarySpeedThreshold
        self.minimumUsableHorizontalAccuracyMeters = minimumUsableHorizontalAccuracyMeters
    }
}

public enum LocationTrackingState: Equatable, Sendable {
    case idleDetection
    case activeTracking
    case maybeStopped(anchor: LocationSample, samples: [LocationSample])
}

public enum LocationTrackingTransition: Equatable, Sendable {
    case none
    case enterActiveTracking
    case enterIdleDetection
}

public struct LocationTrackingStateMachine: Equatable, Sendable {
    public var policy: LocationTrackingPolicy
    public var thresholds: LocationTrackingThresholds
    public private(set) var state: LocationTrackingState

    private var lastSampleTimestamp: Date?

    public init(
        policy: LocationTrackingPolicy = .hybridAutomatic,
        thresholds: LocationTrackingThresholds = .init()
    ) {
        self.policy = policy
        self.thresholds = thresholds
        self.state = policy == .alwaysOnHighPrecision ? .activeTracking : .idleDetection
    }

    @discardableResult
    public mutating func update(policy newPolicy: LocationTrackingPolicy) -> LocationTrackingTransition {
        guard policy != newPolicy else { return .none }
        policy = newPolicy

        switch (newPolicy, state) {
        case (.alwaysOnHighPrecision, .idleDetection):
            state = .activeTracking
            return .enterActiveTracking
        case (.hybridAutomatic, .maybeStopped(let anchor, let samples)):
            if shouldStop(anchor: anchor, samples: samples) {
                state = .idleDetection
                return .enterIdleDetection
            }
            return .none
        default:
            return .none
        }
    }

    @discardableResult
    public mutating func record(sample: LocationSample) -> LocationTrackingTransition {
        if let lastSampleTimestamp, sample.timestamp < lastSampleTimestamp {
            return .none
        }
        lastSampleTimestamp = sample.timestamp

        switch state {
        case .idleDetection:
            state = .activeTracking
            return .enterActiveTracking

        case .activeTracking:
            guard isUsableStationarySample(sample) else {
                return .none
            }
            state = .maybeStopped(anchor: sample, samples: [sample])
            return .none

        case .maybeStopped(let anchor, var samples):
            guard isUsableStationarySample(sample) else {
                return .none
            }

            if sample.speed > thresholds.stationarySpeedThreshold ||
                distanceMeters(from: anchor, to: sample) > thresholds.stationaryRadiusMeters {
                state = .activeTracking
                return .none
            }

            samples.append(sample)
            if shouldStop(anchor: anchor, samples: samples) {
                // REGRESSION GUARD: Only leave active tracking after a sustained stationary window. A single
                // low-speed sample is not enough, and always-on high precision must not downgrade to idle.
                if policy == .hybridAutomatic {
                    state = .idleDetection
                    return .enterIdleDetection
                }
            }
            state = .maybeStopped(anchor: anchor, samples: trimmed(samples))
            return .none
        }
    }

    private func shouldStop(anchor: LocationSample, samples: [LocationSample]) -> Bool {
        guard samples.count >= 2, let first = samples.first, let last = samples.last else {
            return false
        }
        guard last.timestamp.timeIntervalSince(first.timestamp) >= thresholds.stationaryDuration else {
            return false
        }
        guard samples.allSatisfy({ isUsableStationarySample($0) }) else {
            return false
        }
        return samples.allSatisfy { distanceMeters(from: anchor, to: $0) <= thresholds.stationaryRadiusMeters }
    }

    private func isUsableStationarySample(_ sample: LocationSample) -> Bool {
        guard sample.horizontalAccuracy.isFinite,
              sample.horizontalAccuracy >= 0,
              sample.horizontalAccuracy <= thresholds.minimumUsableHorizontalAccuracyMeters,
              sample.speed.isFinite,
              sample.speed >= 0
        else {
            return false
        }
        return sample.speed <= thresholds.stationarySpeedThreshold
    }

    private func trimmed(_ samples: [LocationSample]) -> [LocationSample] {
        guard let latest = samples.last else { return samples }
        let cutoff = latest.timestamp.addingTimeInterval(-thresholds.stationaryDuration)
        let trimmed = samples.filter { $0.timestamp >= cutoff }
        return trimmed.isEmpty ? [latest] : trimmed
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
}
