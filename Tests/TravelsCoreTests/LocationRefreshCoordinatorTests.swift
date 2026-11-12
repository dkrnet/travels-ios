// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.

import XCTest
@testable import TravelsCore

final class LocationRefreshCoordinatorTests: XCTestCase {
    func testIdleRefreshUsesOneShotWithoutCreatingContinuousPendingState() {
        var coordinator = LocationRefreshCoordinator()

        XCTAssertEqual(coordinator.request(managerIsActivelyUpdating: false), .requestOneShot)
        XCTAssertFalse(coordinator.isAwaitingContinuousCallback)
    }

    func testActiveRefreshUsesUnfilteredContinuousCallbackInsteadOfOneShot() {
        var coordinator = LocationRefreshCoordinator()

        XCTAssertEqual(
            coordinator.request(managerIsActivelyUpdating: true),
            .beginUnfilteredContinuousRefresh
        )
        XCTAssertTrue(coordinator.isAwaitingContinuousCallback)
    }

    func testOverlappingActiveRefreshesCoalesceUntilCallbackIsConsumed() {
        var coordinator = LocationRefreshCoordinator()
        XCTAssertEqual(
            coordinator.request(managerIsActivelyUpdating: true),
            .beginUnfilteredContinuousRefresh
        )

        XCTAssertEqual(
            coordinator.request(managerIsActivelyUpdating: true),
            .coalesceWithPendingContinuousRefresh
        )
        XCTAssertTrue(coordinator.consumeContinuousCallback())
        XCTAssertFalse(coordinator.isAwaitingContinuousCallback)
        XCTAssertFalse(coordinator.consumeContinuousCallback())
    }

    func testCancellationClearsPendingContinuousRefresh() {
        var coordinator = LocationRefreshCoordinator()
        _ = coordinator.request(managerIsActivelyUpdating: true)

        XCTAssertTrue(coordinator.cancel())
        XCTAssertFalse(coordinator.isAwaitingContinuousCallback)
        XCTAssertFalse(coordinator.cancel())
    }
}
