// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.

import Foundation
import XCTest
@testable import TravelsCore

final class HybridTrackingWatchdogTests: XCTestCase {
    func testWatchdogStartsInHybridMode() {
        var watchdog = HybridTrackingWatchdog()

        watchdog.start(now: Date(timeIntervalSinceReferenceDate: 100))

        XCTAssertTrue(watchdog.isRunning)
        if case .scheduled(let nextRecheckAt) = watchdog.state {
            XCTAssertEqual(nextRecheckAt, Date(timeIntervalSinceReferenceDate: 190))
        } else {
            XCTFail("Expected the watchdog to be scheduled.")
        }
    }

    func testWatchdogDoesNotRunForAlwaysOnPolicy() {
        var watchdog = HybridTrackingWatchdog(policy: .alwaysOnHighPrecision)

        watchdog.start(now: Date(timeIntervalSinceReferenceDate: 100))

        XCTAssertFalse(watchdog.isRunning)
        XCTAssertEqual(watchdog.state, .idle)
    }

    func testWatchdogCancelsWhenPolicyBecomesAlwaysOn() {
        var watchdog = HybridTrackingWatchdog()
        watchdog.start(now: Date(timeIntervalSinceReferenceDate: 100))

        watchdog.update(policy: .alwaysOnHighPrecision)

        XCTAssertFalse(watchdog.isRunning)
        XCTAssertEqual(watchdog.state, .idle)
    }

    func testWatchdogRequestsAfterIntervalAndReschedules() {
        var watchdog = HybridTrackingWatchdog()
        let start = Date(timeIntervalSinceReferenceDate: 100)
        watchdog.start(now: start)

        XCTAssertFalse(watchdog.shouldRequestRecheck(now: start.addingTimeInterval(89)))
        XCTAssertTrue(watchdog.shouldRequestRecheck(now: start.addingTimeInterval(90)))

        if case .scheduled(let nextRecheckAt) = watchdog.state {
            XCTAssertEqual(nextRecheckAt, start.addingTimeInterval(180))
        } else {
            XCTFail("Expected the watchdog to be rescheduled.")
        }
    }

    func testWatchdogCancelStopsRequests() {
        var watchdog = HybridTrackingWatchdog()
        watchdog.start(now: Date(timeIntervalSinceReferenceDate: 100))
        watchdog.cancel()

        XCTAssertFalse(watchdog.shouldRequestRecheck(now: Date(timeIntervalSinceReferenceDate: 200)))
        XCTAssertEqual(watchdog.state, .idle)
    }
}
