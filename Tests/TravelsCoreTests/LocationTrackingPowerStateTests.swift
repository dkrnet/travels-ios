// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.

import XCTest
@testable import TravelsCore

final class LocationTrackingPowerStateTests: XCTestCase {
    func testPowerStateDefaultsToUnknownBatteryAndNoLowPowerMode() {
        let powerState = LocationTrackingPowerState()

        XCTAssertEqual(powerState.batteryState, .unknown)
        XCTAssertFalse(powerState.lowPowerModeEnabled)
        XCTAssertTrue(powerState.shouldPauseAutomatically)
        XCTAssertFalse(powerState.usesPoweredDistanceThreshold)
    }

    func testPowerStateRefreshesWhenBatteryOrLowPowerModeChanges() {
        let previous = LocationTrackingPowerState(batteryState: .unplugged, lowPowerModeEnabled: false)
        let changedBattery = LocationTrackingPowerState(batteryState: .charging, lowPowerModeEnabled: false)
        let changedLowPowerMode = LocationTrackingPowerState(batteryState: .unplugged, lowPowerModeEnabled: true)

        XCTAssertTrue(changedBattery.requiresConfigurationRefresh(comparedTo: previous))
        XCTAssertTrue(changedLowPowerMode.requiresConfigurationRefresh(comparedTo: previous))
    }
}
