// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.

import Foundation
import XCTest
@testable import TravelsCore

final class LocationTrackingStateMachineTests: XCTestCase {
    private func sample(
        at seconds: TimeInterval,
        latitude: Double = 37.0,
        longitude: Double = -122.0,
        accuracy: Double = 10,
        speed: Double = 0
    ) -> LocationSample {
        LocationSample(
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracy: accuracy,
            speed: speed,
            timestamp: Date(timeIntervalSinceReferenceDate: seconds)
        )
    }

    func testHybridPolicyDefaultsToIdleDetection() {
        let machine = LocationTrackingStateMachine()
        XCTAssertEqual(machine.state, .idleDetection)
    }

    func testAlwaysOnPolicyDefaultsToActiveTracking() {
        let machine = LocationTrackingStateMachine(policy: .alwaysOnHighPrecision)
        XCTAssertEqual(machine.state, .activeTracking)
    }

    func testSignificantLocationChangeTransitionsFromIdleToActiveTracking() {
        var machine = LocationTrackingStateMachine()

        let transition = machine.record(sample: sample(at: 1, speed: 3))

        XCTAssertEqual(transition, .enterActiveTracking)
        XCTAssertEqual(machine.state, .activeTracking)
    }

    func testActiveTrackingDoesNotStopAfterOneStationarySample() {
        var machine = LocationTrackingStateMachine()

        _ = machine.record(sample: sample(at: 1, speed: 3))
        let transition = machine.record(sample: sample(at: 61, speed: 0))

        XCTAssertEqual(transition, .none)
        if case .maybeStopped = machine.state {
            return
        }
        XCTFail("Expected a maybe-stopped state after one stationary sample.")
    }

    func testActiveTrackingStopsAfterConfiguredStationaryWindowWhenHybridPolicyIsOff() {
        var machine = LocationTrackingStateMachine(
            thresholds: LocationTrackingThresholds(
                stationaryDuration: 60,
                stationaryRadiusMeters: 50,
                stationarySpeedThreshold: 0.7,
                minimumUsableHorizontalAccuracyMeters: 100
            )
        )

        _ = machine.record(sample: sample(at: 1, speed: 3))
        _ = machine.record(sample: sample(at: 10, speed: 0))
        let transition = machine.record(sample: sample(at: 75, speed: 0))

        XCTAssertEqual(transition, .enterIdleDetection)
        XCTAssertEqual(machine.state, .idleDetection)
    }

    func testPoorAccuracySamplesDoNotTriggerStoppedDetection() {
        var machine = LocationTrackingStateMachine(
            thresholds: LocationTrackingThresholds(
                stationaryDuration: 60,
                stationaryRadiusMeters: 50,
                stationarySpeedThreshold: 0.7,
                minimumUsableHorizontalAccuracyMeters: 100
            )
        )

        _ = machine.record(sample: sample(at: 1, speed: 3))
        let transition = machine.record(sample: sample(at: 75, accuracy: 500, speed: 0))

        XCTAssertEqual(transition, .none)
        XCTAssertEqual(machine.state, .activeTracking)
    }

    func testMovementAfterPossibleStopKeepsActiveTrackingRunning() {
        var machine = LocationTrackingStateMachine(
            thresholds: LocationTrackingThresholds(
                stationaryDuration: 60,
                stationaryRadiusMeters: 50,
                stationarySpeedThreshold: 0.7,
                minimumUsableHorizontalAccuracyMeters: 100
            )
        )

        _ = machine.record(sample: sample(at: 1, speed: 3))
        _ = machine.record(sample: sample(at: 10, speed: 0))
        let transition = machine.record(sample: sample(at: 20, latitude: 37.002, longitude: -122.002, speed: 4))

        XCTAssertEqual(transition, .none)
        XCTAssertEqual(machine.state, .activeTracking)
    }

    func testAlwaysOnPolicyDoesNotDowngradeToIdleWhenStationary() {
        var machine = LocationTrackingStateMachine(
            policy: .alwaysOnHighPrecision,
            thresholds: LocationTrackingThresholds(
                stationaryDuration: 60,
                stationaryRadiusMeters: 50,
                stationarySpeedThreshold: 0.7,
                minimumUsableHorizontalAccuracyMeters: 100
            )
        )

        _ = machine.record(sample: sample(at: 1, speed: 3))
        _ = machine.record(sample: sample(at: 10, speed: 0))
        _ = machine.record(sample: sample(at: 75, speed: 0))

        XCTAssertNotEqual(machine.state, .idleDetection)
    }

    func testTurningAlwaysOnOffReturnsToIdleWhenAlreadyStationary() {
        var machine = LocationTrackingStateMachine(
            policy: .alwaysOnHighPrecision,
            thresholds: LocationTrackingThresholds(
                stationaryDuration: 60,
                stationaryRadiusMeters: 50,
                stationarySpeedThreshold: 0.7,
                minimumUsableHorizontalAccuracyMeters: 100
            )
        )

        _ = machine.record(sample: sample(at: 1, speed: 3))
        _ = machine.record(sample: sample(at: 10, speed: 0))
        _ = machine.record(sample: sample(at: 75, speed: 0))

        let transition = machine.update(policy: .hybridAutomatic)

        XCTAssertEqual(transition, .enterIdleDetection)
        XCTAssertEqual(machine.state, .idleDetection)
    }
}
