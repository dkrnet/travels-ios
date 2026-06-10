// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import XCTest
@testable import TravelsCore

final class CurrentLocationCaptureAvailabilityTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testCurrentDayAndAvailableServicesAllowsAdd() {
        let now = makeDate(year: 2026, month: 6, day: 9, hour: 10)
        let selectedDate = calendar.startOfDay(for: now)

        XCTAssertTrue(CurrentLocationCaptureAvailability.canAddCurrentLocation(
            selectedDate: selectedDate,
            now: now,
            calendar: calendar,
            locationServicesEnabled: true,
            hasLocationPermission: true,
            isUnlocked: true
        ))
    }

    func testDifferentDayDisablesAdd() {
        let now = makeDate(year: 2026, month: 6, day: 9, hour: 10)
        let selectedDate = calendar.startOfDay(for: makeDate(year: 2026, month: 6, day: 8, hour: 10))

        XCTAssertFalse(CurrentLocationCaptureAvailability.canAddCurrentLocation(
            selectedDate: selectedDate,
            now: now,
            calendar: calendar,
            locationServicesEnabled: true,
            hasLocationPermission: true,
            isUnlocked: true
        ))
    }

    func testDisabledLocationServicesDisablesAdd() {
        let now = makeDate(year: 2026, month: 6, day: 9, hour: 10)
        let selectedDate = calendar.startOfDay(for: now)

        XCTAssertFalse(CurrentLocationCaptureAvailability.canAddCurrentLocation(
            selectedDate: selectedDate,
            now: now,
            calendar: calendar,
            locationServicesEnabled: false,
            hasLocationPermission: true,
            isUnlocked: true
        ))
    }

    func testMissingPermissionDisablesAdd() {
        let now = makeDate(year: 2026, month: 6, day: 9, hour: 10)
        let selectedDate = calendar.startOfDay(for: now)

        XCTAssertFalse(CurrentLocationCaptureAvailability.canAddCurrentLocation(
            selectedDate: selectedDate,
            now: now,
            calendar: calendar,
            locationServicesEnabled: true,
            hasLocationPermission: false,
            isUnlocked: true
        ))
    }

    func testLockedStateDisablesAdd() {
        let now = makeDate(year: 2026, month: 6, day: 9, hour: 10)
        let selectedDate = calendar.startOfDay(for: now)

        XCTAssertFalse(CurrentLocationCaptureAvailability.canAddCurrentLocation(
            selectedDate: selectedDate,
            now: now,
            calendar: calendar,
            locationServicesEnabled: true,
            hasLocationPermission: true,
            isUnlocked: false
        ))
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return components.date!
    }
}
