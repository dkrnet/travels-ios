// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.

import Foundation
import XCTest
@testable import TravelsCore

final class PhotoImportTests: XCTestCase {
    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int = 0,
        second: Int = 0,
        timeZone: TimeZone = TimeZone(identifier: "America/Los_Angeles")!
    ) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return components.date!
    }

    func testPhotoImportPreservesCopiedFilenameWhenCopyingPhotoAndLocation() {
        let metadata = PhotoImportMetadata(
            latitude: 33.8,
            longitude: -118.0,
            horizontalAccuracy: 10,
            verticalAccuracy: 20,
            altitude: 30,
            course: 40,
            speed: 50,
            timestamp: makeDate(year: 2026, month: 6, day: 11, hour: 12)
        )

        let event = LocationEvent.photoImport(
            metadata: metadata,
            assetIdentifier: "asset-id",
            note: "note",
            mode: .photoAndLocation,
            copiedPhotoFilename: "photo.jpg"
        )

        XCTAssertEqual(event.source, .photo)
        XCTAssertEqual(event.externalReference, "asset-id")
        XCTAssertEqual(event.photoFilename, "photo.jpg")
        XCTAssertEqual(event.note, "note")
    }

    func testPhotoImportOmitsCopiedFilenameWhenImportingLocationOnly() {
        let metadata = PhotoImportMetadata(
            latitude: 33.8,
            longitude: -118.0,
            horizontalAccuracy: 10,
            verticalAccuracy: 20,
            altitude: 30,
            course: 40,
            speed: 50,
            timestamp: makeDate(year: 2026, month: 6, day: 11, hour: 12)
        )

        let event = LocationEvent.photoImport(
            metadata: metadata,
            assetIdentifier: "asset-id",
            note: "note",
            mode: .locationOnly,
            copiedPhotoFilename: "photo.jpg"
        )

        XCTAssertEqual(event.source, .photo)
        XCTAssertEqual(event.externalReference, "asset-id")
        XCTAssertEqual(event.photoFilename, "")
        XCTAssertEqual(event.note, "note")
    }
}
