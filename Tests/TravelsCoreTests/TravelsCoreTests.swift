// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import XCTest
@testable import TravelsCore

final class TravelsCoreTests: XCTestCase {
    func testAreasOfInterestAreNormalized() {
        XCTAssertEqual(Geolocation.normalizedAreasOfInterest([" Pier ", "", "Park", "Pier"]), ["Park", "Pier"])
    }

    func testLocationFilteringRejectsStaleSamples() {
        let previous = LocationEvent(latitude: 1, longitude: 1, horizontalAccuracy: 10, timestamp: Date(timeIntervalSinceReferenceDate: 100), source: .locationServices)
        let candidate = LocationSample(latitude: 2, longitude: 2, horizontalAccuracy: 10, timestamp: Date(timeIntervalSinceReferenceDate: 50))
        XCTAssertEqual(LocationFiltering.decision(candidate: candidate, previous: previous), .reject)
    }

    func testLocationFilteringAcceptsFirstSample() {
        let candidate = LocationSample(latitude: 2, longitude: 2, horizontalAccuracy: 10, timestamp: Date())
        XCTAssertEqual(LocationFiltering.decision(candidate: candidate, previous: nil), .accept)
    }

    func testGPXImportParsesTrackPoints() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/sample.gpx")
        let result = try GPXImporter.parse(url: url)
        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events[0].source, .imported)
        XCTAssertEqual(result.events[0].note, "Sample import")
    }

    func testSQLiteStoreSavesAndSearchesEvents() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let geoID = try store.saveGeolocation(Geolocation(name: "Apple Park", locality: "Cupertino", country: "United States", areasOfInterest: ["Apple Park"]))
        let event = LocationEvent(
            latitude: 37.3317,
            longitude: -122.0301,
            timestamp: Date(),
            localizedDate: TravelsDateTools.localizedDayString(for: Date(), timeZoneIdentifier: nil),
            source: .manual,
            geolocationID: geoID,
            note: "hello"
        )
        _ = try store.saveEvent(event)
        let results = try store.search(SearchCriteria(term: "Apple"))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(try store.eventCount(), 1)
    }

    func testGPXExportRejectsEmptySets() {
        XCTAssertThrowsError(try GPXExporter.export(events: [])) { error in
            XCTAssertEqual(error as? TravelsError, .emptyExport)
        }
    }
}
