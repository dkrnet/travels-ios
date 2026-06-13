import Foundation
import XCTest
@testable import TravelsCore

final class HybridPreciseLocationSamplingRulesTests: XCTestCase {
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
                    speed: 1.2,
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
}
