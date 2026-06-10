// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import XCTest
@testable import TravelsCore

final class TripDetectionTests: XCTestCase {
    private let timeZone = TimeZone(identifier: "America/Los_Angeles")!

    private func makeDate(
        year: Int = 2026,
        month: Int = 6,
        day: Int = 7,
        hour: Int,
        minute: Int = 0,
        second: Int = 0
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

    private func makeEvent(
        id: Int64,
        hour: Int,
        minute: Int = 0,
        speed: Double,
        second: Int = 0
    ) -> LocationEvent {
        LocationEvent(
            id: id,
            latitude: 33.8403,
            longitude: -118.0037,
            horizontalAccuracy: 10,
            speed: speed,
            timestamp: makeDate(hour: hour, minute: minute, second: second),
            source: .locationServices
        )
    }

    private func detect(_ events: [LocationEvent]) -> [DetectedTrip] {
        TripDetectionService().detectTrips(from: events, timeZone: timeZone)
    }

    func testEmptyEventListReturnsNoTrips() {
        XCTAssertTrue(detect([]).isEmpty)
    }

    func testStoppedOnlyEventsReturnNoTrips() {
        let events = [
            makeEvent(id: 1, hour: 8, speed: 0),
            makeEvent(id: 2, hour: 9, speed: 0),
            makeEvent(id: 3, hour: 10, speed: -1)
        ]

        XCTAssertTrue(detect(events).isEmpty)
    }

    func testMovingSequenceCreatesOneTrip() {
        let events = [
            makeEvent(id: 1, hour: 8, minute: 0, speed: 4),
            makeEvent(id: 2, hour: 8, minute: 10, speed: 5),
            makeEvent(id: 3, hour: 8, minute: 20, speed: 6)
        ]

        let trips = detect(events)
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips[0].movingEventIDs, Set<LocationEvent.ID>([1, 2, 3]))
        XCTAssertTrue(trips[0].endpointEventIDs.isEmpty)
    }

    func testStoppedThenMovingUsesTheStoppedEventAsStartingEndpoint() {
        let events = [
            makeEvent(id: 1, hour: 7, minute: 30, speed: 0),
            makeEvent(id: 2, hour: 8, minute: 0, speed: 4),
            makeEvent(id: 3, hour: 8, minute: 10, speed: 5)
        ]

        let trips = detect(events)
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips[0].endpointEventIDs, Set<LocationEvent.ID>([1]))
        XCTAssertEqual(trips[0].displayEventIDs, Set<LocationEvent.ID>([1, 2, 3]))
    }

    func testMovingThenStoppedUsesTheStoppedEventAsEndingEndpoint() {
        let events = [
            makeEvent(id: 1, hour: 8, minute: 0, speed: 4),
            makeEvent(id: 2, hour: 8, minute: 10, speed: 5),
            makeEvent(id: 3, hour: 8, minute: 20, speed: 0)
        ]

        let trips = detect(events)
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips[0].endpointEventIDs, Set<LocationEvent.ID>([3]))
        XCTAssertEqual(trips[0].displayEventIDs, Set<LocationEvent.ID>([1, 2, 3]))
    }

    func testStoppedThenMovingThenStoppedUsesBothEndpoints() {
        let events = [
            makeEvent(id: 1, hour: 7, minute: 30, speed: 0),
            makeEvent(id: 2, hour: 8, minute: 0, speed: 4),
            makeEvent(id: 3, hour: 8, minute: 20, speed: 0)
        ]

        let trips = detect(events)
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips[0].endpointEventIDs, Set<LocationEvent.ID>([1, 3]))
        XCTAssertEqual(trips[0].displayEventIDs, Set<LocationEvent.ID>([1, 2, 3]))
    }

    func testMovingStoppedMovingCreatesTwoTripsAndSharesTheStoppedEvent() {
        let events = [
            makeEvent(id: 1, hour: 8, minute: 0, speed: 4),
            makeEvent(id: 2, hour: 8, minute: 10, speed: 0),
            makeEvent(id: 3, hour: 8, minute: 20, speed: 5)
        ]

        let trips = detect(events)
        XCTAssertEqual(trips.count, 2)
        XCTAssertEqual(trips[0].displayEventIDs, Set<LocationEvent.ID>([1, 2]))
        XCTAssertEqual(trips[1].displayEventIDs, Set<LocationEvent.ID>([2, 3]))
    }

    func testMultipleStoppedEventsSplitBetweenNeighboringTrips() {
        let events = [
            makeEvent(id: 1, hour: 8, minute: 0, speed: 4),
            makeEvent(id: 2, hour: 8, minute: 10, speed: 0),
            makeEvent(id: 3, hour: 8, minute: 20, speed: 0),
            makeEvent(id: 4, hour: 8, minute: 30, speed: 5)
        ]

        let trips = detect(events)
        XCTAssertEqual(trips.count, 2)
        XCTAssertEqual(trips[0].endpointEventIDs, Set<LocationEvent.ID>([2]))
        XCTAssertEqual(trips[1].endpointEventIDs, Set<LocationEvent.ID>([3]))
        XCTAssertEqual(trips[0].displayEventIDs, Set<LocationEvent.ID>([1, 2]))
        XCTAssertEqual(trips[1].displayEventIDs, Set<LocationEvent.ID>([3, 4]))
    }

    func testGapLessThanTripSeparationIntervalStaysOneTrip() {
        let events = [
            makeEvent(id: 1, hour: 8, minute: 0, speed: 4),
            makeEvent(id: 2, hour: 8, minute: 29, speed: 5)
        ]

        XCTAssertEqual(detect(events).count, 1)
    }

    func testGapGreaterThanOrEqualToTripSeparationIntervalSplitsTrips() {
        let events = [
            makeEvent(id: 1, hour: 8, minute: 0, speed: 4),
            makeEvent(id: 2, hour: 8, minute: 30, speed: 5)
        ]

        let trips = detect(events)
        XCTAssertEqual(trips.count, 2)
        XCTAssertTrue(trips.allSatisfy { $0.endpointEventIDs.isEmpty })
    }

    func testLargeGapWithoutStoppedEventsDoesNotCreateEndpointMarkers() {
        let events = [
            makeEvent(id: 1, hour: 8, minute: 0, speed: 4),
            makeEvent(id: 2, hour: 9, minute: 0, speed: 5)
        ]

        let trips = detect(events)
        XCTAssertEqual(trips.count, 2)
        XCTAssertTrue(trips.allSatisfy { $0.endpointEventIDs.isEmpty })
    }

    func testOutOfOrderEventsAreSortedBeforeDetection() {
        let events = [
            makeEvent(id: 3, hour: 8, minute: 20, speed: 5),
            makeEvent(id: 1, hour: 8, minute: 0, speed: 4),
            makeEvent(id: 2, hour: 8, minute: 10, speed: 5)
        ]

        let trips = detect(events)
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips[0].movingEventIDs, Set<LocationEvent.ID>([1, 2, 3]))
    }

    func testDuplicateTimestampsDoNotCrash() {
        let events = [
            makeEvent(id: 1, hour: 8, minute: 0, speed: 4),
            makeEvent(id: 2, hour: 8, minute: 0, speed: 5),
            makeEvent(id: 3, hour: 8, minute: 5, speed: 6)
        ]

        let trips = detect(events)
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips[0].movingEventIDs, Set<LocationEvent.ID>([1, 2, 3]))
    }

    func testUnknownMovementStateDoesNotStartATrip() {
        let events = [
            makeEvent(id: 1, hour: 8, minute: 0, speed: -1),
            makeEvent(id: 2, hour: 8, minute: 10, speed: -1)
        ]

        XCTAssertTrue(detect(events).isEmpty)
    }

    func testDisplayEventIDsAreTheUnionOfMovingAndEndpointEventIDs() {
        let events = [
            makeEvent(id: 1, hour: 8, minute: 0, speed: 4),
            makeEvent(id: 2, hour: 8, minute: 10, speed: 0),
            makeEvent(id: 3, hour: 8, minute: 20, speed: 5)
        ]

        let trips = detect(events)
        XCTAssertEqual(trips.count, 2)
        XCTAssertEqual(trips[0].displayEventIDs, trips[0].movingEventIDs.union(trips[0].endpointEventIDs))
        XCTAssertEqual(trips[1].displayEventIDs, trips[1].movingEventIDs.union(trips[1].endpointEventIDs))
    }

    func testTripDisplayNameUsesMovingEventStartAndEndTimes() {
        let events = (0...16).map { index -> LocationEvent in
            let totalMinutes = 6 * 60 + 30 + (index * 20)
            let hour = totalMinutes / 60
            let minute = totalMinutes % 60
            return makeEvent(
                id: Int64(index + 1),
                hour: hour,
                minute: minute,
                speed: 5
            )
        }

        let trips = detect(events)
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips[0].displayName, "Early morning to mid-day")
    }

    func testDuplicateTripNamesAreNumbered() {
        let events = [
            makeEvent(id: 1, hour: 15, minute: 10, speed: 4),
            makeEvent(id: 2, hour: 15, minute: 20, speed: 5),
            makeEvent(id: 3, hour: 15, minute: 30, speed: 0),
            makeEvent(id: 4, hour: 15, minute: 40, speed: 4),
            makeEvent(id: 5, hour: 15, minute: 50, speed: 5)
        ]

        let trips = detect(events)
        XCTAssertEqual(trips.map(\.displayName), ["Midafternoon 1", "Midafternoon 2"])
    }

    func testUniqueTripNamesAreNotNumbered() {
        let events = [
            makeEvent(id: 1, hour: 8, minute: 0, speed: 4),
            makeEvent(id: 2, hour: 8, minute: 20, speed: 5)
        ]

        let trips = detect(events)
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips[0].displayName, "Early morning")
    }

    func testTripsAreReturnedInChronologicalOrder() {
        let events = [
            makeEvent(id: 4, hour: 15, minute: 10, speed: 4),
            makeEvent(id: 5, hour: 15, minute: 20, speed: 5),
            makeEvent(id: 6, hour: 15, minute: 30, speed: 0),
            makeEvent(id: 1, hour: 8, minute: 0, speed: 4),
            makeEvent(id: 2, hour: 8, minute: 20, speed: 5)
        ]

        let trips = detect(events)
        XCTAssertEqual(trips.count, 2)
        XCTAssertLessThan(trips[0].movingStartDate, trips[1].movingStartDate)
        XCTAssertEqual(trips.map(\.displayName), ["Early morning", "Midafternoon"])
    }

    func testMapDisplaySelectionAllReturnsAllEvents() {
        let events = [
            makeEvent(id: 1, hour: 8, minute: 0, speed: 4),
            makeEvent(id: 2, hour: 8, minute: 10, speed: 0)
        ]

        XCTAssertEqual(filteredEvents(from: events, selection: .all, detectedTrips: []), events)
    }

    func testMapDisplaySelectionStoppedOnlyReturnsOnlyStoppedEvents() {
        let events = [
            makeEvent(id: 1, hour: 8, minute: 0, speed: 4),
            makeEvent(id: 2, hour: 8, minute: 10, speed: 0),
            makeEvent(id: 3, hour: 8, minute: 20, speed: -1)
        ]

        let filtered = filteredEvents(from: events, selection: .stoppedOnly, detectedTrips: [])
        XCTAssertEqual(filtered.map(\.id), [2, 3])
    }

    func testMapDisplaySelectionTripReturnsTripEvents() {
        let events = [
            makeEvent(id: 1, hour: 8, minute: 0, speed: 4),
            makeEvent(id: 2, hour: 8, minute: 10, speed: 0),
            makeEvent(id: 3, hour: 8, minute: 20, speed: 5)
        ]
        let trips = detect(events)

        let filtered = filteredEvents(from: events, selection: .trips([trips[0].id]), detectedTrips: trips)
        XCTAssertEqual(filtered.map(\.id), [1, 2])
    }

    func testMapDisplaySelectionTripReturnsNoEventsWhenTripMissing() {
        let events = [
            makeEvent(id: 1, hour: 8, minute: 0, speed: 4),
            makeEvent(id: 2, hour: 8, minute: 10, speed: 0)
        ]

        let filtered = filteredEvents(from: events, selection: .trips(["missing"]), detectedTrips: [])
        XCTAssertTrue(filtered.isEmpty)
    }

    func testMapDisplaySelectionMultipleTripsReturnsUnionOfTripEvents() {
        let events = [
            makeEvent(id: 1, hour: 8, minute: 0, speed: 4),
            makeEvent(id: 2, hour: 8, minute: 10, speed: 0),
            makeEvent(id: 3, hour: 8, minute: 20, speed: 5),
            makeEvent(id: 4, hour: 15, minute: 0, speed: 4),
            makeEvent(id: 5, hour: 15, minute: 10, speed: 0),
            makeEvent(id: 6, hour: 15, minute: 20, speed: 5)
        ]

        let trips = detect(events)
        let filtered = filteredEvents(from: events, selection: .trips([trips[0].id, trips[1].id]), detectedTrips: trips)
        XCTAssertEqual(filtered.map(\.id), [1, 2, 3, 4, 5, 6])
    }
}
