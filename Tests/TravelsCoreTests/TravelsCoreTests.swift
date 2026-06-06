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

    func testDemoDataSeedsThreeDaysBeforeLaunchAndCanBeHidden() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let referenceDate = Date(timeIntervalSinceReferenceDate: 1_000_000)
        try DemoData.seed(into: store, anchoredTo: referenceDate)

        let allEvents = try store.allEvents()
        XCTAssertGreaterThanOrEqual(allEvents.count, 18)
        XCTAssertTrue(allEvents.contains { $0.event.note.isEmpty })
        XCTAssertTrue(allEvents.contains { !$0.event.note.isEmpty })
        XCTAssertTrue(allEvents.allSatisfy { $0.geolocation == nil })
        XCTAssertEqual(try store.allEvents(includeDemo: false).count, 0)
        XCTAssertEqual(try store.eventCount(includeDemo: true), allEvents.count)
        XCTAssertEqual(try store.eventCount(includeDemo: false), 0)

        let calendar = Calendar.current
        let launchDay = calendar.startOfDay(for: referenceDate)
        let offsets = Set(allEvents.compactMap { detail in
            calendar.dateComponents([.day], from: launchDay, to: calendar.startOfDay(for: detail.event.timestamp)).day
        })
        XCTAssertTrue(offsets.contains(-3))
        XCTAssertTrue(offsets.contains(-2))
        XCTAssertTrue(offsets.contains(-1))
        XCTAssertEqual(try store.latestEventDate(includeDemo: true).map { calendar.startOfDay(for: $0) }, calendar.date(byAdding: .day, value: -1, to: launchDay))
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

    func testOldestAndLatestEventDatesAreReported() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let older = Date(timeIntervalSinceReferenceDate: 1_000)
        let newer = Date(timeIntervalSinceReferenceDate: 2_000)

        _ = try store.saveEvent(
            LocationEvent(
                latitude: 1,
                longitude: 1,
                timestamp: newer,
                localizedDate: "2001-01-02",
                source: .manual
            )
        )
        _ = try store.saveEvent(
            LocationEvent(
                latitude: 2,
                longitude: 2,
                timestamp: older,
                localizedDate: "2001-01-01",
                source: .manual
            )
        )

        XCTAssertEqual(try store.oldestEventDate()?.timeIntervalSinceReferenceDate, older.timeIntervalSinceReferenceDate)
        XCTAssertEqual(try store.latestEventDate()?.timeIntervalSinceReferenceDate, newer.timeIntervalSinceReferenceDate)
    }

    func testSearchSupportsDateAndPlaceFilters() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let matchingGeolocation = Geolocation(
            name: "Apple Park",
            locality: "Cupertino",
            administrativeArea: "California",
            country: "United States",
            inlandWater: "San Francisco Bay"
        )
        let matchingGeoID = try store.saveGeolocation(matchingGeolocation)
        let otherGeoID = try store.saveGeolocation(
            Geolocation(
                name: "Paris",
                locality: "Paris",
                administrativeArea: "Ile-de-France",
                country: "France"
            )
        )

        _ = try store.saveEvent(
            LocationEvent(
                latitude: 37.3317,
                longitude: -122.0301,
                timestamp: Date(timeIntervalSinceReferenceDate: 1_000),
                localizedDate: "2001-01-01",
                source: .manual,
                geolocationID: matchingGeoID,
                note: "Hello Cupertino"
            )
        )
        _ = try store.saveEvent(
            LocationEvent(
                latitude: 48.8566,
                longitude: 2.3522,
                timestamp: Date(timeIntervalSinceReferenceDate: 2_000),
                localizedDate: "2001-01-02",
                source: .manual,
                geolocationID: otherGeoID,
                note: "Bonjour"
            )
        )

        let results = try store.search(
            SearchCriteria(
                startDate: Date(timeIntervalSinceReferenceDate: 500),
                endDate: Date(timeIntervalSinceReferenceDate: 1_500),
                country: "United States",
                administrativeArea: "California",
                locality: "Cupertino",
                bodyOfWater: "San Francisco Bay"
            )
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.event.note, "Hello Cupertino")
    }

    func testEventsNeedingGeolocationCanBeResolved() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let event = LocationEvent(
            latitude: 37.8044,
            longitude: -122.2711,
            timestamp: Date(timeIntervalSinceReferenceDate: 4_000),
            localizedDate: "2001-01-01",
            source: .locationServices,
            note: "Needs resolving"
        )
        let eventID = try store.saveEvent(event)
        let geolocationID = try store.saveGeolocation(
            Geolocation(
                name: "Oakland",
                locality: "Oakland",
                administrativeArea: "California",
                country: "United States"
            )
        )

        XCTAssertEqual(try store.eventsNeedingGeolocation().count, 1)
        try store.attachGeolocation(geolocationID, toEvent: eventID)
        XCTAssertEqual(try store.eventsNeedingGeolocation().count, 0)
        XCTAssertEqual(try store.allEvents().first?.geolocation?.name, "Oakland")
    }

    func testGeolocationNearLookupFindsStoredCache() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let storedID = try store.saveGeolocation(
            Geolocation(
                latitude: 37.3317,
                longitude: -122.0301,
                name: "Apple Park",
                locality: "Cupertino",
                administrativeArea: "California",
                country: "United States"
            )
        )

        let cached = try store.geolocation(near: 37.33171, longitude: -122.03009)
        XCTAssertEqual(cached?.id, storedID)
        XCTAssertEqual(cached?.name, "Apple Park")
    }

    func testGPXExportRejectsEmptySets() {
        XCTAssertThrowsError(try GPXExporter.export(events: [])) { error in
            XCTAssertEqual(error as? TravelsError, .emptyExport)
        }
    }

    func testGPXExportIncludesSavedEvents() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let event = LocationEvent(
            latitude: 51.5007,
            longitude: -0.1246,
            timestamp: Date(timeIntervalSinceReferenceDate: 1_000),
            localizedDate: "2001-01-01",
            source: .manual,
            note: "Westminster"
        )
        _ = try store.saveEvent(event)

        let details = try store.allEvents()
        let xml = try GPXExporter.export(events: details)
        XCTAssertTrue(xml.contains("<trkpt"))
        XCTAssertTrue(xml.contains("Westminster"))
    }

    func testPhotoFilenameRoundTripsThroughStore() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let event = LocationEvent(
            latitude: 40.7128,
            longitude: -74.0060,
            timestamp: Date(timeIntervalSinceReferenceDate: 3_000),
            localizedDate: "2001-01-01",
            source: .photo,
            note: "Snapshot",
            photoFilename: "photo-test.img"
        )
        _ = try store.saveEvent(event)

        let saved = try store.allEvents().first
        XCTAssertEqual(saved?.event.photoFilename, "photo-test.img")
        XCTAssertEqual(saved?.event.source, .photo)
    }
}
