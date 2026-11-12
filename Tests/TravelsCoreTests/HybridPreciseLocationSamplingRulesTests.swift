import Foundation
import XCTest
@testable import TravelsCore

final class HybridPreciseLocationSamplingRulesTests: XCTestCase {
    func testBackgroundActiveTrackingHandoffOnlyStartsForAutomaticHybridBackgroundEntry() {
        XCTAssertTrue(
            HybridPreciseLocationSamplingRules.shouldBeginBackgroundActiveTrackingHandoff(
                isEnteringActiveTracking: true,
                isHybridPolicy: true,
                automaticLocationTrackingEnabled: true,
                backgroundLocationEnabled: true,
                hasLocationAuthorization: true,
                applicationIsBackgrounded: true,
                isAutomaticCoreLocationSample: true
            )
        )

        let disabledConditions: [(Bool, Bool, Bool, Bool, Bool, Bool, Bool)] = [
            (false, true, true, true, true, true, true),
            (true, false, true, true, true, true, true),
            (true, true, false, true, true, true, true),
            (true, true, true, false, true, true, true),
            (true, true, true, true, false, true, true),
            (true, true, true, true, true, false, true),
            (true, true, true, true, true, true, false)
        ]
        for condition in disabledConditions {
            XCTAssertFalse(
                HybridPreciseLocationSamplingRules.shouldBeginBackgroundActiveTrackingHandoff(
                    isEnteringActiveTracking: condition.0,
                    isHybridPolicy: condition.1,
                    automaticLocationTrackingEnabled: condition.2,
                    backgroundLocationEnabled: condition.3,
                    hasLocationAuthorization: condition.4,
                    applicationIsBackgrounded: condition.5,
                    isAutomaticCoreLocationSample: condition.6
                )
            )
        }
    }

    func testInitialActiveTrackingGuardStaysActiveUntilFirstRecheckOrMinimumInterval() {
        let enteredAt = Date(timeIntervalSinceReferenceDate: 100)

        let waiting = HybridPreciseLocationSamplingRules.initialActiveTrackingGuardStatus(
            enteredAt: enteredAt,
            firstWatchdogRecheckCompleted: false,
            minimumActiveInterval: 90,
            now: enteredAt.addingTimeInterval(30)
        )
        XCTAssertTrue(waiting.isActive)
        XCTAssertEqual(waiting.reason, "waiting for first watchdog recheck or minimum active interval")

        let afterRecheck = HybridPreciseLocationSamplingRules.initialActiveTrackingGuardStatus(
            enteredAt: enteredAt,
            firstWatchdogRecheckCompleted: true,
            minimumActiveInterval: 90,
            now: enteredAt.addingTimeInterval(30)
        )
        XCTAssertFalse(afterRecheck.isActive)
        XCTAssertEqual(afterRecheck.reason, "first watchdog recheck completed")

        let afterMinimumInterval = HybridPreciseLocationSamplingRules.initialActiveTrackingGuardStatus(
            enteredAt: enteredAt,
            firstWatchdogRecheckCompleted: false,
            minimumActiveInterval: 90,
            now: enteredAt.addingTimeInterval(90)
        )
        XCTAssertFalse(afterMinimumInterval.isActive)
        XCTAssertEqual(afterMinimumInterval.reason, "minimum active interval elapsed")
    }

    func testInitialActiveTrackingGuardIsInactiveWhenNotArmed() {
        let status = HybridPreciseLocationSamplingRules.initialActiveTrackingGuardStatus(
            enteredAt: nil,
            firstWatchdogRecheckCompleted: false,
            minimumActiveInterval: 90,
            now: Date(timeIntervalSinceReferenceDate: 100)
        )

        XCTAssertFalse(status.isActive)
        XCTAssertEqual(status.reason, "initial active tracking guard is not armed")
    }

    func testImmediateAutomaticSampleIsRequestedOnlyForRealEntryTransitions() {
        XCTAssertTrue(
            HybridPreciseLocationSamplingRules.shouldRequestImmediateAutomaticSample(
                isEnteringActiveTracking: true,
                automaticLocationTrackingEnabled: true,
                hasLocationAuthorization: true,
                isCompletingFinalPreciseExit: false
            )
        )

        XCTAssertFalse(
            HybridPreciseLocationSamplingRules.shouldRequestImmediateAutomaticSample(
                isEnteringActiveTracking: false,
                automaticLocationTrackingEnabled: true,
                hasLocationAuthorization: true,
                isCompletingFinalPreciseExit: false
            )
        )

        XCTAssertFalse(
            HybridPreciseLocationSamplingRules.shouldRequestImmediateAutomaticSample(
                isEnteringActiveTracking: true,
                automaticLocationTrackingEnabled: false,
                hasLocationAuthorization: true,
                isCompletingFinalPreciseExit: false
            )
        )

        XCTAssertFalse(
            HybridPreciseLocationSamplingRules.shouldRequestImmediateAutomaticSample(
                isEnteringActiveTracking: true,
                automaticLocationTrackingEnabled: true,
                hasLocationAuthorization: false,
                isCompletingFinalPreciseExit: true
            )
        )
    }

    func testBackgroundActivitySessionIsRetainedOnlyForAuthorizedActiveBackgroundTracking() {
        XCTAssertTrue(
            HybridPreciseLocationSamplingRules.shouldRetainBackgroundActivitySession(
                managerIsActive: true,
                automaticLocationTrackingEnabled: true,
                backgroundLocationEnabled: true,
                hasLocationAuthorization: true
            )
        )

        for disabledCondition in 0..<4 {
            XCTAssertFalse(
                HybridPreciseLocationSamplingRules.shouldRetainBackgroundActivitySession(
                    managerIsActive: disabledCondition != 0,
                    automaticLocationTrackingEnabled: disabledCondition != 1,
                    backgroundLocationEnabled: disabledCondition != 2,
                    hasLocationAuthorization: disabledCondition != 3
                )
            )
        }
    }

    func testFinalExitOnlyStartsForHybridActiveToIdleTransitions() {
        XCTAssertTrue(
            HybridPreciseLocationSamplingRules.shouldStartBoundedFinalPreciseExit(
                currentManagerIsActive: true,
                desiredIdleDetection: true,
                isHybridPolicy: true,
                automaticLocationTrackingEnabled: true,
                hasLocationAuthorization: true,
                isCompletingFinalPreciseExit: false
            )
        )

        XCTAssertFalse(
            HybridPreciseLocationSamplingRules.shouldStartBoundedFinalPreciseExit(
                currentManagerIsActive: true,
                desiredIdleDetection: true,
                isHybridPolicy: false,
                automaticLocationTrackingEnabled: true,
                hasLocationAuthorization: true,
                isCompletingFinalPreciseExit: false
            )
        )

        XCTAssertFalse(
            HybridPreciseLocationSamplingRules.shouldStartBoundedFinalPreciseExit(
                currentManagerIsActive: true,
                desiredIdleDetection: true,
                isHybridPolicy: true,
                automaticLocationTrackingEnabled: false,
                hasLocationAuthorization: true,
                isCompletingFinalPreciseExit: false
            )
        )

        XCTAssertFalse(
            HybridPreciseLocationSamplingRules.shouldStartBoundedFinalPreciseExit(
                currentManagerIsActive: true,
                desiredIdleDetection: true,
                isHybridPolicy: true,
                automaticLocationTrackingEnabled: true,
                hasLocationAuthorization: false,
                isCompletingFinalPreciseExit: true
            )
        )
    }

    func testMovementResumedDetectionUsesSpeedThenDistance() {
        let previous = LocationEvent(
            id: 1,
            latitude: 33.0,
            longitude: -118.0,
            horizontalAccuracy: 10,
            verticalAccuracy: 10,
            altitude: 0,
            course: -1,
            speed: 0,
            timestamp: Date(timeIntervalSinceReferenceDate: 1000),
            source: .locationServices
        )

        XCTAssertTrue(
            HybridPreciseLocationSamplingRules.sampleIndicatesMovementResumed(
                sample: LocationSample(
                    latitude: 33.0,
                    longitude: -118.0,
                    horizontalAccuracy: 10,
                    course: -1,
                    speed: 2.0,
                    timestamp: Date(timeIntervalSinceReferenceDate: 1010)
                ),
                latestAcceptedEvent: previous,
                stationarySpeedThreshold: 0.7,
                stationaryRadiusMeters: 50,
                minimumUsableHorizontalAccuracyMeters: 100
            )
        )

        XCTAssertTrue(
            HybridPreciseLocationSamplingRules.sampleIndicatesMovementResumed(
                sample: LocationSample(
                    latitude: 33.001,
                    longitude: -118.001,
                    horizontalAccuracy: 10,
                    course: -1,
                    speed: -1,
                    timestamp: Date(timeIntervalSinceReferenceDate: 1010)
                ),
                latestAcceptedEvent: previous,
                stationarySpeedThreshold: 0.7,
                stationaryRadiusMeters: 50,
                minimumUsableHorizontalAccuracyMeters: 100
            )
        )

        XCTAssertFalse(
            HybridPreciseLocationSamplingRules.sampleIndicatesMovementResumed(
                sample: LocationSample(
                    latitude: 33.0,
                    longitude: -118.0,
                    horizontalAccuracy: 10,
                    course: -1,
                    speed: 0.1,
                    timestamp: Date(timeIntervalSinceReferenceDate: 1010)
                ),
                latestAcceptedEvent: previous,
                stationarySpeedThreshold: 0.7,
                stationaryRadiusMeters: 50,
                minimumUsableHorizontalAccuracyMeters: 100
            )
        )
    }

    func testFinalPreciseExitSampleRequiresFreshUsableMaterialMovement() {
        let previous = LocationEvent(
            id: 1,
            latitude: 33.0,
            longitude: -118.0,
            horizontalAccuracy: 10,
            verticalAccuracy: 10,
            altitude: 0,
            course: -1,
            speed: 0,
            timestamp: Date(timeIntervalSinceReferenceDate: 1000),
            source: .locationServices
        )
        let now = Date(timeIntervalSinceReferenceDate: 1020)

        let nearStationary = HybridPreciseLocationSamplingRules.finalPreciseExitSampleAssessment(
            sample: LocationSample(
                latitude: 33.0001,
                longitude: -118.0001,
                horizontalAccuracy: 10,
                course: -1,
                speed: 0.2,
                timestamp: Date(timeIntervalSinceReferenceDate: 1010)
            ),
            latestAcceptedEvent: previous,
            stationarySpeedThreshold: 0.7,
            stationaryRadiusMeters: 50,
            minimumUsableHorizontalAccuracyMeters: 100,
            now: now
        )
        XCTAssertFalse(nearStationary.indicatesMovementResumed)

        let stale = HybridPreciseLocationSamplingRules.finalPreciseExitSampleAssessment(
            sample: LocationSample(
                latitude: 33.002,
                longitude: -118.002,
                horizontalAccuracy: 10,
                course: -1,
                speed: 3,
                timestamp: Date(timeIntervalSinceReferenceDate: 900)
            ),
            latestAcceptedEvent: previous,
            stationarySpeedThreshold: 0.7,
            stationaryRadiusMeters: 50,
            minimumUsableHorizontalAccuracyMeters: 100,
            now: now
        )
        XCTAssertEqual(stale, .rejects(reason: "sample is stale"))

        let lowAccuracy = HybridPreciseLocationSamplingRules.finalPreciseExitSampleAssessment(
            sample: LocationSample(
                latitude: 33.002,
                longitude: -118.002,
                horizontalAccuracy: 250,
                course: -1,
                speed: 3,
                timestamp: Date(timeIntervalSinceReferenceDate: 1010)
            ),
            latestAcceptedEvent: previous,
            stationarySpeedThreshold: 0.7,
            stationaryRadiusMeters: 50,
            minimumUsableHorizontalAccuracyMeters: 100,
            now: now
        )
        XCTAssertEqual(lowAccuracy, .rejects(reason: "horizontal accuracy is too low"))

        let realMovement = HybridPreciseLocationSamplingRules.finalPreciseExitSampleAssessment(
            sample: LocationSample(
                latitude: 33.002,
                longitude: -118.002,
                horizontalAccuracy: 10,
                course: -1,
                speed: -1,
                timestamp: Date(timeIntervalSinceReferenceDate: 1010)
            ),
            latestAcceptedEvent: previous,
            stationarySpeedThreshold: 0.7,
            stationaryRadiusMeters: 50,
            minimumUsableHorizontalAccuracyMeters: 100,
            now: now
        )
        XCTAssertTrue(realMovement.indicatesMovementResumed)
    }

    func testPostExitGuardSuppressesAmbiguousImmediateSamples() {
        let exitSample = LocationSample(
            latitude: 33.0,
            longitude: -118.0,
            horizontalAccuracy: 10,
            course: -1,
            speed: 0,
            timestamp: Date(timeIntervalSinceReferenceDate: 1000)
        )
        let assessment = HybridPreciseLocationSamplingRules.postExitPreciseReentryAssessment(
            sample: LocationSample(
                latitude: 33.0001,
                longitude: -118.0001,
                horizontalAccuracy: 10,
                course: -1,
                speed: -1,
                timestamp: Date(timeIntervalSinceReferenceDate: 1010)
            ),
            exitTimestamp: Date(timeIntervalSinceReferenceDate: 1005),
            finalExitSample: exitSample,
            cooldown: 180,
            activeTrackingMinimumDistanceMeters: 50,
            stationarySpeedThreshold: 0.7,
            minimumUsableHorizontalAccuracyMeters: 100,
            now: Date(timeIntervalSinceReferenceDate: 1020)
        )

        XCTAssertFalse(assessment.allowsReentry)
    }

    func testPostExitGuardAllowsReentryAfterCooldownExpires() {
        let assessment = HybridPreciseLocationSamplingRules.postExitPreciseReentryAssessment(
            sample: LocationSample(
                latitude: 33.0,
                longitude: -118.0,
                horizontalAccuracy: 10,
                course: -1,
                speed: -1,
                timestamp: Date(timeIntervalSinceReferenceDate: 1200)
            ),
            exitTimestamp: Date(timeIntervalSinceReferenceDate: 1000),
            finalExitSample: nil,
            cooldown: 180,
            activeTrackingMinimumDistanceMeters: 50,
            stationarySpeedThreshold: 0.7,
            minimumUsableHorizontalAccuracyMeters: 100,
            now: Date(timeIntervalSinceReferenceDate: 1181)
        )

        XCTAssertTrue(assessment.allowsReentry)
    }

    func testPostExitGuardAllowsReliableSpeedButRejectsPoorAccuracySpeed() {
        let exitSample = LocationSample(
            latitude: 33.0,
            longitude: -118.0,
            horizontalAccuracy: 10,
            course: -1,
            speed: 0,
            timestamp: Date(timeIntervalSinceReferenceDate: 1000)
        )
        let poorAccuracySpeed = HybridPreciseLocationSamplingRules.postExitPreciseReentryAssessment(
            sample: LocationSample(
                latitude: 33.0,
                longitude: -118.0,
                horizontalAccuracy: 250,
                course: -1,
                speed: 4,
                timestamp: Date(timeIntervalSinceReferenceDate: 1010)
            ),
            exitTimestamp: Date(timeIntervalSinceReferenceDate: 1005),
            finalExitSample: exitSample,
            cooldown: 180,
            activeTrackingMinimumDistanceMeters: 50,
            stationarySpeedThreshold: 0.7,
            minimumUsableHorizontalAccuracyMeters: 100,
            now: Date(timeIntervalSinceReferenceDate: 1020)
        )
        XCTAssertFalse(poorAccuracySpeed.allowsReentry)

        let reliableSpeed = HybridPreciseLocationSamplingRules.postExitPreciseReentryAssessment(
            sample: LocationSample(
                latitude: 33.0,
                longitude: -118.0,
                horizontalAccuracy: 25,
                course: -1,
                speed: 4,
                timestamp: Date(timeIntervalSinceReferenceDate: 1010)
            ),
            exitTimestamp: Date(timeIntervalSinceReferenceDate: 1005),
            finalExitSample: exitSample,
            cooldown: 180,
            activeTrackingMinimumDistanceMeters: 50,
            stationarySpeedThreshold: 0.7,
            minimumUsableHorizontalAccuracyMeters: 100,
            now: Date(timeIntervalSinceReferenceDate: 1020)
        )
        XCTAssertTrue(reliableSpeed.allowsReentry)
    }

    func testPostExitGuardAllowsMaterialDistance() {
        let exitSample = LocationSample(
            latitude: 33.0,
            longitude: -118.0,
            horizontalAccuracy: 10,
            course: -1,
            speed: -1,
            timestamp: Date(timeIntervalSinceReferenceDate: 1000)
        )
        let assessment = HybridPreciseLocationSamplingRules.postExitPreciseReentryAssessment(
            sample: LocationSample(
                latitude: 33.003,
                longitude: -118.003,
                horizontalAccuracy: 10,
                course: -1,
                speed: -1,
                timestamp: Date(timeIntervalSinceReferenceDate: 1010)
            ),
            exitTimestamp: Date(timeIntervalSinceReferenceDate: 1005),
            finalExitSample: exitSample,
            cooldown: 180,
            activeTrackingMinimumDistanceMeters: 50,
            stationarySpeedThreshold: 0.7,
            minimumUsableHorizontalAccuracyMeters: 100,
            now: Date(timeIntervalSinceReferenceDate: 1020)
        )

        XCTAssertTrue(assessment.allowsReentry)
    }
}
