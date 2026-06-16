// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.

import Foundation

public struct AdaptiveLocationDistanceResult: Equatable, Sendable {
    public var effectiveDistanceMeters: Double
    public var shouldUpdateDistanceFilter: Bool
    public var shouldRequestTransitionSample: Bool
    public var reason: String
}

public struct AdaptiveLocationDistanceCalculator: Equatable, Sendable {
    public struct State: Equatable, Sendable {
        public var effectiveDistanceMeters: Double
        public var smoothedSpeedMetersPerSecond: Double?
        public var sustainedHighSpeedSampleCount: Int
        public var sustainedLowSpeedSampleCount: Int
        public var highSpeedStartedAt: Date?
        public var lowSpeedStartedAt: Date?
        public var lastTransitionSampleRequestedAt: Date?
        public var highwayToTownTransitionArmed: Bool

        public init(
            effectiveDistanceMeters: Double,
            smoothedSpeedMetersPerSecond: Double? = nil,
            sustainedHighSpeedSampleCount: Int = 0,
            sustainedLowSpeedSampleCount: Int = 0,
            highSpeedStartedAt: Date? = nil,
            lowSpeedStartedAt: Date? = nil,
            lastTransitionSampleRequestedAt: Date? = nil,
            highwayToTownTransitionArmed: Bool = false
        ) {
            self.effectiveDistanceMeters = effectiveDistanceMeters
            self.smoothedSpeedMetersPerSecond = smoothedSpeedMetersPerSecond
            self.sustainedHighSpeedSampleCount = sustainedHighSpeedSampleCount
            self.sustainedLowSpeedSampleCount = sustainedLowSpeedSampleCount
            self.highSpeedStartedAt = highSpeedStartedAt
            self.lowSpeedStartedAt = lowSpeedStartedAt
            self.lastTransitionSampleRequestedAt = lastTransitionSampleRequestedAt
            self.highwayToTownTransitionArmed = highwayToTownTransitionArmed
        }
    }

    public var mode: LocationDetailMode
    public private(set) var state: State
    public static let transitionCooldownReason = "transition sample suppressed due to cooldown"

    public init(mode: LocationDetailMode = .balanced) {
        self.mode = mode
        self.state = State(effectiveDistanceMeters: Self.parameters(for: mode).minimumDistanceMeters)
    }

    public mutating func update(mode newMode: LocationDetailMode) {
        guard mode != newMode else { return }
        mode = newMode
        let parameters = Self.parameters(for: newMode)
        state.effectiveDistanceMeters = clamp(state.effectiveDistanceMeters, min: parameters.minimumDistanceMeters, max: parameters.maximumDistanceMeters)
    }

    @discardableResult
    public mutating func record(sample: LocationSample) -> AdaptiveLocationDistanceResult {
        let parameters = Self.parameters(for: mode)
        guard sample.speed.isFinite, sample.speed >= 0 else {
            return result(updateFilter: false, transition: false, reason: "invalid speed ignored")
        }
        guard sample.horizontalAccuracy.isFinite,
              sample.horizontalAccuracy >= 0,
              sample.horizontalAccuracy <= parameters.maximumSpeedSmoothingAccuracyMeters
        else {
            return result(updateFilter: false, transition: false, reason: "poor accuracy speed ignored")
        }

        let previousSmoothedSpeed = state.smoothedSpeedMetersPerSecond
        let smoothingAlpha = previousSmoothedSpeed.map { sample.speed < $0 ? parameters.downwardSmoothingAlpha : parameters.smoothingAlpha }
            ?? parameters.smoothingAlpha
        let smoothedSpeed = previousSmoothedSpeed.map { $0 + smoothingAlpha * (sample.speed - $0) } ?? sample.speed
        state.smoothedSpeedMetersPerSecond = smoothedSpeed

        updateSpeedBandState(sampleSpeed: sample.speed, timestamp: sample.timestamp, parameters: parameters)

        var targetDistance = parameters.minimumDistanceMeters + parameters.speedSensitivity * smoothedSpeed * smoothedSpeed
        var reason = "adaptive distance recalculated"
        targetDistance = clamp(targetDistance, min: parameters.minimumDistanceMeters, max: parameters.maximumDistanceMeters)

        let sustainedLow = lowerSpeedIsSustained(at: sample.timestamp, parameters: parameters)
        let sustainedHigh = higherSpeedIsSustained(at: sample.timestamp, parameters: parameters)

        if sustainedLow && sample.speed <= parameters.townSpeedThresholdMetersPerSecond {
            targetDistance = min(targetDistance, parameters.townSpeedCapMeters)
            reason = "town-speed cap applied"
        } else if sustainedHigh && targetDistance > state.effectiveDistanceMeters {
            reason = "adaptive distance increased due to sustained high speed"
        } else if sustainedLow && targetDistance < state.effectiveDistanceMeters {
            reason = "adaptive distance decreased due to sustained lower speed"
        }

        let previousDistance = state.effectiveDistanceMeters
        let proposedDistance: Double
        if targetDistance > previousDistance {
            guard sustainedHigh else {
                return result(updateFilter: false, transition: false, reason: "high-speed increase waiting for sustained speed")
            }
            proposedDistance = previousDistance + (targetDistance - previousDistance) * parameters.increaseFraction
        } else if targetDistance < previousDistance {
            guard sustainedLow || sample.speed <= parameters.townSpeedThresholdMetersPerSecond else {
                return result(updateFilter: false, transition: false, reason: "lower-speed decrease waiting for sustained speed")
            }
            proposedDistance = sustainedLow && sample.speed <= parameters.townSpeedThresholdMetersPerSecond
                ? targetDistance
                : previousDistance + (targetDistance - previousDistance) * parameters.decreaseFraction
        } else {
            proposedDistance = targetDistance
        }

        let materialChange = materialDistanceChange(from: previousDistance, to: proposedDistance, parameters: parameters)
        if materialChange {
            state.effectiveDistanceMeters = proposedDistance
        }

        let transitionDecision = transitionSampleDecision(
            timestamp: sample.timestamp,
            sampleSpeed: sample.speed,
            sustainedLow: sustainedLow,
            parameters: parameters
        )
        let transition = transitionDecision == .request
        if transition {
            state.lastTransitionSampleRequestedAt = sample.timestamp
            state.highwayToTownTransitionArmed = false
            reason = "significant speed-drop transition sample requested"
        } else if transitionDecision == .suppressedByCooldown {
            reason = Self.transitionCooldownReason
        }

        return result(updateFilter: materialChange, transition: transition, reason: reason)
    }

    private mutating func updateSpeedBandState(
        sampleSpeed: Double,
        timestamp: Date,
        parameters: Parameters
    ) {
        if sampleSpeed >= parameters.highwaySpeedThresholdMetersPerSecond {
            state.sustainedHighSpeedSampleCount += 1
            state.highSpeedStartedAt = state.highSpeedStartedAt ?? timestamp
            state.sustainedLowSpeedSampleCount = 0
            state.lowSpeedStartedAt = nil
            state.highwayToTownTransitionArmed = true
        } else if sampleSpeed <= parameters.townSpeedThresholdMetersPerSecond {
            state.sustainedLowSpeedSampleCount += 1
            state.lowSpeedStartedAt = state.lowSpeedStartedAt ?? timestamp
            state.sustainedHighSpeedSampleCount = 0
            state.highSpeedStartedAt = nil
        } else {
            state.sustainedHighSpeedSampleCount = 0
            state.highSpeedStartedAt = nil
            state.sustainedLowSpeedSampleCount = 0
            state.lowSpeedStartedAt = nil
        }
    }

    private func higherSpeedIsSustained(at timestamp: Date, parameters: Parameters) -> Bool {
        if state.sustainedHighSpeedSampleCount >= parameters.samplesForIncrease {
            return true
        }
        guard let highSpeedStartedAt = state.highSpeedStartedAt else {
            return false
        }
        return timestamp.timeIntervalSince(highSpeedStartedAt) >= parameters.secondsForIncrease
    }

    private func lowerSpeedIsSustained(at timestamp: Date, parameters: Parameters) -> Bool {
        if state.sustainedLowSpeedSampleCount >= parameters.samplesForDecrease {
            return true
        }
        guard let lowSpeedStartedAt = state.lowSpeedStartedAt else {
            return false
        }
        return timestamp.timeIntervalSince(lowSpeedStartedAt) >= parameters.secondsForDecrease
    }

    private func transitionSampleDecision(
        timestamp: Date,
        sampleSpeed: Double,
        sustainedLow: Bool,
        parameters: Parameters
    ) -> TransitionSampleDecision {
        guard state.highwayToTownTransitionArmed,
              sustainedLow,
              sampleSpeed <= parameters.townSpeedThresholdMetersPerSecond
        else {
            return .none
        }
        if let last = state.lastTransitionSampleRequestedAt,
           timestamp.timeIntervalSince(last) < parameters.transitionSampleCooldown {
            return .suppressedByCooldown
        }
        return .request
    }

    private func materialDistanceChange(from previous: Double, to proposed: Double, parameters: Parameters) -> Bool {
        guard previous > 0 else { return true }
        let absoluteChange = abs(proposed - previous)
        let relativeChange = absoluteChange / previous
        return absoluteChange >= parameters.minimumDistanceFilterChangeMeters
            || relativeChange >= parameters.minimumDistanceFilterChangeFraction
    }

    private func result(updateFilter: Bool, transition: Bool, reason: String) -> AdaptiveLocationDistanceResult {
        AdaptiveLocationDistanceResult(
            effectiveDistanceMeters: state.effectiveDistanceMeters,
            shouldUpdateDistanceFilter: updateFilter,
            shouldRequestTransitionSample: transition,
            reason: reason
        )
    }

    private struct Parameters: Equatable, Sendable {
        var minimumDistanceMeters: Double
        var maximumDistanceMeters: Double
        var townSpeedCapMeters: Double
        var speedSensitivity: Double
        var smoothingAlpha: Double
        var downwardSmoothingAlpha: Double
        var increaseFraction: Double
        var decreaseFraction: Double
        var samplesForIncrease: Int = 3
        var samplesForDecrease: Int = 2
        var secondsForIncrease: TimeInterval = 60
        var secondsForDecrease: TimeInterval = 60
        var transitionSampleCooldown: TimeInterval = 180
        var townSpeedThresholdMetersPerSecond: Double = 20.1
        var highwaySpeedThresholdMetersPerSecond: Double = 24.6
        var maximumSpeedSmoothingAccuracyMeters: Double = 100
        var minimumDistanceFilterChangeFraction: Double = 0.25
        var minimumDistanceFilterChangeMeters: Double = 100
    }

    private enum TransitionSampleDecision: Equatable, Sendable {
        case none
        case request
        case suppressedByCooldown
    }

    private static func parameters(for mode: LocationDetailMode) -> Parameters {
        switch mode {
        case .highDetail:
            Parameters(
                minimumDistanceMeters: 250,
                maximumDistanceMeters: 1_500,
                townSpeedCapMeters: 650,
                speedSensitivity: 0.75,
                smoothingAlpha: 0.4,
                downwardSmoothingAlpha: 0.75,
                increaseFraction: 0.4,
                decreaseFraction: 0.8
            )
        case .balanced:
            Parameters(
                minimumDistanceMeters: 500,
                maximumDistanceMeters: 3_000,
                townSpeedCapMeters: 900,
                speedSensitivity: 1.5,
                smoothingAlpha: 0.35,
                downwardSmoothingAlpha: 0.72,
                increaseFraction: 0.35,
                decreaseFraction: 0.75
            )
        case .batterySaver:
            Parameters(
                minimumDistanceMeters: 750,
                maximumDistanceMeters: 5_000,
                townSpeedCapMeters: 1_400,
                speedSensitivity: 2.7,
                smoothingAlpha: 0.35,
                downwardSmoothingAlpha: 0.72,
                increaseFraction: 0.3,
                decreaseFraction: 0.7
            )
        case .roadTrip:
            Parameters(
                minimumDistanceMeters: 1_000,
                maximumDistanceMeters: 10_000,
                townSpeedCapMeters: 1_800,
                speedSensitivity: 4.5,
                smoothingAlpha: 0.3,
                downwardSmoothingAlpha: 0.68,
                increaseFraction: 0.25,
                decreaseFraction: 0.6
            )
        }
    }

    private func clamp(_ value: Double, min minimum: Double, max maximum: Double) -> Double {
        Swift.max(minimum, Swift.min(value, maximum))
    }
}
