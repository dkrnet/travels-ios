// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import XCTest
@testable import TravelsCore

final class EventDetailDisplayRulesTests: XCTestCase {
    func testNormalizedDisplayTextTrimsWhitespaceAndDropsEmptyValues() {
        XCTAssertNil(EventDetailDisplayRules.normalizedDisplayText(nil))
        XCTAssertNil(EventDetailDisplayRules.normalizedDisplayText(""))
        XCTAssertNil(EventDetailDisplayRules.normalizedDisplayText("   \n\t  "))
        XCTAssertEqual(EventDetailDisplayRules.normalizedDisplayText("  Travels  "), "Travels")
        XCTAssertTrue(EventDetailDisplayRules.isMeaningfulDisplayText("  Travels  "))
    }

    func testMeaningfulScalarValues() {
        XCTAssertFalse(EventDetailDisplayRules.hasMeaningfulAltitude(0))
        XCTAssertTrue(EventDetailDisplayRules.hasMeaningfulAltitude(42))

        XCTAssertFalse(EventDetailDisplayRules.hasMeaningfulAccuracy(-1))
        XCTAssertTrue(EventDetailDisplayRules.hasMeaningfulAccuracy(0))

        XCTAssertFalse(EventDetailDisplayRules.hasMeaningfulCourse(-1))
        XCTAssertTrue(EventDetailDisplayRules.hasMeaningfulCourse(0))

        XCTAssertFalse(EventDetailDisplayRules.hasMeaningfulSpeed(-1))
        XCTAssertTrue(EventDetailDisplayRules.hasMeaningfulSpeed(0))
    }

    func testMeaningfulSolarPeriod() {
        XCTAssertFalse(EventDetailDisplayRules.hasMeaningfulSolarPeriod(.unknown))
        XCTAssertTrue(EventDetailDisplayRules.hasMeaningfulSolarPeriod(.day))
    }

    func testMeaningfulPlaceMetadataRequiresRealContent() {
        let empty = Geolocation()
        XCTAssertFalse(EventDetailDisplayRules.hasMeaningfulPlaceMetadata(empty))

        var geolocation = Geolocation()
        geolocation.timeZoneIdentifier = "America/Los_Angeles"
        XCTAssertTrue(EventDetailDisplayRules.hasMeaningfulPlaceMetadata(geolocation))

        geolocation = Geolocation()
        geolocation.areasOfInterest = ["   ", "  Griffith Observatory  "]
        XCTAssertTrue(EventDetailDisplayRules.hasMeaningfulPlaceMetadata(geolocation))
        XCTAssertTrue(EventDetailDisplayRules.hasMeaningfulAreasOfInterest(geolocation.areasOfInterest))
    }
}
