// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.

import Foundation
import XCTest
@testable import TravelsCore

final class AdaptiveLocationDistanceCalculatorTests: XCTestCase {
    private func sample(
        at seconds: TimeInterval,
        speed: Double,
        accuracy: Double = 10,
        latitude: Double = 37,
        longitude: Double = -122
    ) -> LocationSample {
        LocationSample(
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracy: accuracy,
            speed: speed,
            timestamp: Date(timeIntervalSinceReferenceDate: seconds)
        )
    }

    private func feed(
        _ calculator: inout AdaptiveLocationDistanceCalculator,
        speeds: [Double],
        start: TimeInterval = 0,
        interval: TimeInterval = 30
    ) -> [AdaptiveLocationDistanceResult] {
        speeds.enumerated().map { index, speed in
            calculator.record(sample: sample(at: start + Double(index) * interval, speed: speed))
        }
    }

    func testLocationDetailModeDefaultsToBalancedWhenMissingOrUnknown() throws {
        let missing = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        let unknown = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"locationDetailMode":"maximumChaos"}"#.utf8))

        XCTAssertEqual(missing.locationDetailMode, .balanced)
        XCTAssertEqual(unknown.locationDetailMode, .balanced)
    }

    func testLocationDetailModeRawValuesDecode() throws {
        let high = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"locationDetailMode":"highDetail"}"#.utf8))
        let balanced = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"locationDetailMode":"balanced"}"#.utf8))
        let saver = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"locationDetailMode":"batterySaver"}"#.utf8))
        let road = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"locationDetailMode":"roadTrip"}"#.utf8))

        XCTAssertEqual(high.locationDetailMode, .highDetail)
        XCTAssertEqual(balanced.locationDetailMode, .balanced)
        XCTAssertEqual(saver.locationDetailMode, .batterySaver)
        XCTAssertEqual(road.locationDetailMode, .roadTrip)
    }

    func testInvalidAndPoorAccuracySpeedsDoNotCreateWildChanges() {
        var calculator = AdaptiveLocationDistanceCalculator(mode: .balanced)

        _ = calculator.record(sample: sample(at: 0, speed: -1))
        XCTAssertEqual(calculator.state.effectiveDistanceMeters, 500)

        _ = calculator.record(sample: sample(at: 30, speed: 35, accuracy: 500))
        XCTAssertEqual(calculator.state.effectiveDistanceMeters, 500)
        XCTAssertNil(calculator.state.smoothedSpeedMetersPerSecond)
    }

    func testOneHighSpeedSpikeDoesNotSignificantlyIncreaseDistance() {
        var calculator = AdaptiveLocationDistanceCalculator(mode: .balanced)

        let result = calculator.record(sample: sample(at: 0, speed: 35.8))

        XCTAssertFalse(result.shouldUpdateDistanceFilter)
        XCTAssertEqual(calculator.state.effectiveDistanceMeters, 500)
    }

    func testSustainedHighSpeedIncreasesEffectiveDistanceAndModesScale() {
        var high = AdaptiveLocationDistanceCalculator(mode: .highDetail)
        var balanced = AdaptiveLocationDistanceCalculator(mode: .balanced)
        var saver = AdaptiveLocationDistanceCalculator(mode: .batterySaver)
        var road = AdaptiveLocationDistanceCalculator(mode: .roadTrip)

        _ = feed(&high, speeds: Array(repeating: 35.8, count: 8))
        _ = feed(&balanced, speeds: Array(repeating: 35.8, count: 8))
        _ = feed(&saver, speeds: Array(repeating: 35.8, count: 8))
        _ = feed(&road, speeds: Array(repeating: 35.8, count: 8))

        XCTAssertLessThan(high.state.effectiveDistanceMeters, balanced.state.effectiveDistanceMeters)
        XCTAssertGreaterThan(saver.state.effectiveDistanceMeters, balanced.state.effectiveDistanceMeters)
        XCTAssertGreaterThan(road.state.effectiveDistanceMeters, saver.state.effectiveDistanceMeters)
        XCTAssertLessThanOrEqual(road.state.effectiveDistanceMeters, 10_000)
    }

    func testDistanceClampsToModeMinimumAndMaximum() {
        var calculator = AdaptiveLocationDistanceCalculator(mode: .roadTrip)

        XCTAssertEqual(calculator.state.effectiveDistanceMeters, 1_000)
        _ = feed(&calculator, speeds: Array(repeating: 70.0, count: 20))

        XCTAssertLessThanOrEqual(calculator.state.effectiveDistanceMeters, 10_000)
        XCTAssertGreaterThan(calculator.state.effectiveDistanceMeters, 8_000)
    }

    func testSustainedSpeedDropShrinksFasterThanIncreaseAndRequestsTransitionOnce() {
        var calculator = AdaptiveLocationDistanceCalculator(mode: .batterySaver)

        _ = feed(&calculator, speeds: Array(repeating: 35.8, count: 12), interval: 30)
        let highwayDistance = calculator.state.effectiveDistanceMeters
        XCTAssertGreaterThan(highwayDistance, 3_000)

        let townResults = feed(&calculator, speeds: Array(repeating: 15.6, count: 4), start: 600, interval: 30)

        XCTAssertLessThanOrEqual(calculator.state.effectiveDistanceMeters, 1_400)
        XCTAssertTrue(townResults.contains(where: \.shouldRequestTransitionSample))
        XCTAssertEqual(townResults.filter(\.shouldRequestTransitionSample).count, 1)
    }

    func testTransitionSampleCooldownPreventsRepeatedRequestsUntilHighwayRearms() {
        var calculator = AdaptiveLocationDistanceCalculator(mode: .balanced)

        _ = feed(&calculator, speeds: Array(repeating: 35.8, count: 6), interval: 30)
        let firstTown = feed(&calculator, speeds: Array(repeating: 15.6, count: 4), start: 300, interval: 30)
        XCTAssertEqual(firstTown.filter(\.shouldRequestTransitionSample).count, 1)

        let moreTown = feed(&calculator, speeds: Array(repeating: 15.6, count: 4), start: 420, interval: 30)
        XCTAssertFalse(moreTown.contains(where: \.shouldRequestTransitionSample))

        _ = feed(&calculator, speeds: Array(repeating: 35.8, count: 4), start: 900, interval: 30)
        let secondTown = feed(&calculator, speeds: Array(repeating: 15.6, count: 4), start: 1_080, interval: 30)
        XCTAssertEqual(secondTown.filter(\.shouldRequestTransitionSample).count, 1)
    }

    func testEffectiveDistanceDoesNotOscillateNearThresholds() {
        var calculator = AdaptiveLocationDistanceCalculator(mode: .balanced)

        let results = feed(&calculator, speeds: [19.5, 20.5, 19.8, 20.2, 19.7, 20.4, 19.6], interval: 20)

        XCTAssertLessThanOrEqual(results.filter(\.shouldUpdateDistanceFilter).count, 1)
    }

    func testRoadTripScenarioKeepsTownSegmentSaveEligible() {
        var calculator = AdaptiveLocationDistanceCalculator(mode: .batterySaver)

        _ = feed(&calculator, speeds: Array(repeating: 35.8, count: 120), interval: 30)
        XCTAssertGreaterThan(calculator.state.effectiveDistanceMeters, 3_000)

        _ = feed(&calculator, speeds: Array(repeating: 15.6, count: 20), start: 3_600, interval: 30)
        let townDistance = calculator.state.effectiveDistanceMeters
        XCTAssertLessThanOrEqual(townDistance, 1_400)

        let tenMinuteTownTravelMeters = 15.6 * 10 * 60
        XCTAssertGreaterThan(Int(tenMinuteTownTravelMeters / townDistance), 3)

        _ = feed(&calculator, speeds: Array(repeating: 0.0, count: 20), start: 4_200, interval: 30)
        XCTAssertLessThanOrEqual(calculator.state.effectiveDistanceMeters, 1_400)

        _ = feed(&calculator, speeds: Array(repeating: 35.8, count: 12), start: 4_800, interval: 30)
        XCTAssertGreaterThan(calculator.state.effectiveDistanceMeters, townDistance)
    }
}
