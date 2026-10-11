// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.

import XCTest
@testable import TravelsCore

final class BackgroundLocationSessionRulesTests: XCTestCase {
    func testSessionRequiresAutomaticTrackingBackgroundSettingAndAuthorization() {
        XCTAssertTrue(BackgroundLocationSessionRules.shouldRetainSession(
            automaticTrackingEnabled: true,
            backgroundLocationEnabled: true,
            hasLocationAuthorization: true,
            preciseBackgroundTrackingAllowed: true
        ))
        XCTAssertFalse(BackgroundLocationSessionRules.shouldRetainSession(
            automaticTrackingEnabled: false,
            backgroundLocationEnabled: true,
            hasLocationAuthorization: true,
            preciseBackgroundTrackingAllowed: true
        ))
        XCTAssertFalse(BackgroundLocationSessionRules.shouldRetainSession(
            automaticTrackingEnabled: true,
            backgroundLocationEnabled: false,
            hasLocationAuthorization: true,
            preciseBackgroundTrackingAllowed: true
        ))
        XCTAssertFalse(BackgroundLocationSessionRules.shouldRetainSession(
            automaticTrackingEnabled: true,
            backgroundLocationEnabled: true,
            hasLocationAuthorization: false,
            preciseBackgroundTrackingAllowed: true
        ))
        XCTAssertFalse(BackgroundLocationSessionRules.shouldRetainSession(
            automaticTrackingEnabled: true,
            backgroundLocationEnabled: true,
            hasLocationAuthorization: true,
            preciseBackgroundTrackingAllowed: false
        ))
    }

    func testBackgroundCreatedSessionIsReplacedAfterForegrounding() {
        XCTAssertTrue(BackgroundLocationSessionRules.shouldReplaceSessionAfterForegrounding(
            hasSession: true,
            sessionWasCreatedInForeground: false
        ))
        XCTAssertFalse(BackgroundLocationSessionRules.shouldReplaceSessionAfterForegrounding(
            hasSession: true,
            sessionWasCreatedInForeground: true
        ))
        XCTAssertFalse(BackgroundLocationSessionRules.shouldReplaceSessionAfterForegrounding(
            hasSession: false,
            sessionWasCreatedInForeground: false
        ))
    }
}
