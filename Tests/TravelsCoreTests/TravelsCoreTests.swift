// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.
import Foundation
import XCTest
@testable import TravelsCore

final class TravelsCoreTests: XCTestCase {
    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int = 0,
        second: Int = 0,
        timeZone: TimeZone
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

    private func losAngelesSolarEvents(on date: Date) -> SolarEventTimes? {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return SolarTwilight.calculateSolarEvents(
            for: date,
            latitude: 33.8403,
            longitude: -118.0037,
            timeZone: timeZone
        )
    }

    private func repositoryRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func fixtureURL(_ relativePath: String) -> URL {
        repositoryRootURL().appendingPathComponent("Fixtures").appendingPathComponent(relativePath)
    }

    private func makeDetail(
        date: Date,
        latitude: Double = 33.8403,
        longitude: Double = -118.0037,
        timeZoneIdentifier: String = "America/Los_Angeles",
        solarPeriod: SolarPeriod? = nil,
        solarPeriodPercent: Double? = nil,
        twilightPhase: TwilightPhase = .none,
        twilightPercent: Double? = nil
    ) -> EventDetail {
        let event = LocationEvent(
            latitude: latitude,
            longitude: longitude,
            timestamp: date,
            localizedDate: TravelsDateTools.localizedDayString(for: date, timeZoneIdentifier: timeZoneIdentifier),
            source: .locationServices,
            solarPeriod: solarPeriod ?? SolarPeriod(twilightPhase: twilightPhase),
            solarPeriodPercent: solarPeriodPercent ?? twilightPercent
        )
        let geolocation = Geolocation(
            latitude: latitude,
            longitude: longitude,
            timeZoneIdentifier: timeZoneIdentifier,
            name: "Test Place"
        )
        return EventDetail(event: event, geolocation: geolocation)
    }

    private func createLegacyEventsDatabase(at url: URL) throws {
        let database = try SQLiteDatabase(path: url.path)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            horizontalAccuracy REAL NOT NULL DEFAULT -1,
            verticalAccuracy REAL NOT NULL DEFAULT -1,
            altitude REAL NOT NULL DEFAULT 0,
            course REAL NOT NULL DEFAULT -1,
            speed REAL NOT NULL DEFAULT -1,
            timestamp REAL NOT NULL,
            localizedDate TEXT,
            source INTEGER NOT NULL,
            geolocationID INTEGER,
            note TEXT NOT NULL DEFAULT '',
            tags TEXT NOT NULL DEFAULT '',
            externalReference TEXT NOT NULL DEFAULT '',
            photoFilename TEXT NOT NULL DEFAULT '',
            isDemo INTEGER NOT NULL DEFAULT 0,
            twilight_phase TEXT NOT NULL DEFAULT 'none',
            twilight_percent REAL,
            UNIQUE(latitude, longitude, timestamp, source, externalReference)
        )
        """)
        try database.execute(
            """
            INSERT INTO events (
                latitude, longitude, timestamp, localizedDate, source, externalReference,
                note, twilight_phase, twilight_percent
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            parameters: [
                .real(33.0),
                .real(-118.0),
                .real(1_000),
                .text("2001-01-01"),
                .integer(Int64(EventSource.locationServices.rawValue)),
                .text("legacy"),
                .text("legacy note"),
                .text(TwilightPhase.none.rawValue),
                .null
            ]
        )
    }

    func testAddButtonUsesMutedToneWhenDisabled() {
        XCTAssertEqual(ButtonForegroundTone.addButton(canAddCurrentLocation: true), .primary)
        XCTAssertEqual(ButtonForegroundTone.addButton(canAddCurrentLocation: false), .tertiary)
    }

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

    func testLocationFilteringUsesThePausedDistanceThresholdWhilePausing() {
        let previous = LocationEvent(latitude: 0, longitude: 0, horizontalAccuracy: 5, timestamp: Date(timeIntervalSinceReferenceDate: 100), source: .locationServices)
        let candidate = LocationSample(latitude: 0.0005, longitude: 0, horizontalAccuracy: 5, timestamp: Date(timeIntervalSinceReferenceDate: 200))
        XCTAssertEqual(
            LocationFiltering.decision(
                candidate: candidate,
                previous: previous,
                isPausing: true,
                minimumDistanceMeters: 100,
                pausedMinimumDistanceMeters: 50
            ),
            .accept
        )
    }

    func testLocationFilteringCanReplacePreviousWhenNewSampleIsMoreAccurateAndSlower() {
        let previous = LocationEvent(
            latitude: 37.0,
            longitude: -122.0,
            horizontalAccuracy: 12,
            speed: 4,
            timestamp: Date(timeIntervalSinceReferenceDate: 100),
            source: .locationServices
        )
        let candidate = LocationSample(
            latitude: 37.0,
            longitude: -122.0,
            horizontalAccuracy: 12,
            speed: 0.5,
            timestamp: Date(timeIntervalSinceReferenceDate: 120)
        )

        XCTAssertEqual(
            LocationFiltering.decision(
                candidate: candidate,
                previous: previous,
                improvementWindowSeconds: 300
            ),
            .acceptAndReplacePrevious
        )
    }

    func testLocationFilteringCanReplacePreviousWhenNewSampleIsMoreAccurateEvenIfSpeedDoesNotImprove() {
        let previous = LocationEvent(
            latitude: 37.0,
            longitude: -122.0,
            horizontalAccuracy: 12,
            speed: 4,
            timestamp: Date(timeIntervalSinceReferenceDate: 100),
            source: .locationServices
        )
        let candidate = LocationSample(
            latitude: 37.0,
            longitude: -122.0,
            horizontalAccuracy: 8,
            speed: 6,
            timestamp: Date(timeIntervalSinceReferenceDate: 120)
        )

        XCTAssertEqual(
            LocationFiltering.decision(
                candidate: candidate,
                previous: previous,
                improvementWindowSeconds: 300
            ),
            .acceptAndReplacePrevious
        )
    }

    func testLocationFilteringCanReplacePreviousWhenStationarySamplesHaveUnavailableSpeed() {
        let previous = LocationEvent(
            latitude: 37.0,
            longitude: -122.0,
            horizontalAccuracy: 12,
            speed: -1,
            timestamp: Date(timeIntervalSinceReferenceDate: 100),
            source: .locationServices
        )
        let candidate = LocationSample(
            latitude: 37.0,
            longitude: -122.0,
            horizontalAccuracy: 12,
            speed: -1,
            timestamp: Date(timeIntervalSinceReferenceDate: 120)
        )

        XCTAssertEqual(
            LocationFiltering.decision(
                candidate: candidate,
                previous: previous,
                improvementWindowSeconds: 300
            ),
            .acceptAndReplacePrevious
        )
    }

    func testTwilightResultIsNoneDuringFullDaylight() throws {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = makeDate(year: 2026, month: 6, day: 7, hour: 12, timeZone: timeZone)
        let events = try XCTUnwrap(losAngelesSolarEvents(on: date))
        let eventDate = events.sunrise!.addingTimeInterval(events.sunset!.timeIntervalSince(events.sunrise!) / 2.0)

        let result = SolarTwilight.twilightResult(at: eventDate, solarEvents: events)
        XCTAssertEqual(result.phase, .none)
        XCTAssertNil(result.percent)
    }

    func testTwilightResultIsNoneDuringFullNight() throws {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = makeDate(year: 2026, month: 6, day: 7, hour: 12, timeZone: timeZone)
        let events = try XCTUnwrap(losAngelesSolarEvents(on: date))
        let eventDate = events.civilDawn!.addingTimeInterval(-3600)

        let result = SolarTwilight.twilightResult(at: eventDate, solarEvents: events)
        XCTAssertEqual(result.phase, .none)
        XCTAssertNil(result.percent)
    }

    func testTwilightResultIsMorningTwilightHalfwayBetweenCivilDawnAndSunrise() throws {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = makeDate(year: 2026, month: 6, day: 7, hour: 12, timeZone: timeZone)
        let events = try XCTUnwrap(losAngelesSolarEvents(on: date))
        let civilDawn = try XCTUnwrap(events.civilDawn)
        let sunrise = try XCTUnwrap(events.sunrise)
        let eventDate = civilDawn.addingTimeInterval(sunrise.timeIntervalSince(civilDawn) / 2.0)

        let result = SolarTwilight.twilightResult(at: eventDate, solarEvents: events)
        XCTAssertEqual(result.phase, .morningCivilTwilight)
        XCTAssertEqual(try XCTUnwrap(result.percent), 0.5, accuracy: 0.0001)
    }

    func testTwilightResultIsEveningTwilightHalfwayBetweenSunsetAndCivilDusk() throws {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = makeDate(year: 2026, month: 6, day: 7, hour: 12, timeZone: timeZone)
        let events = try XCTUnwrap(losAngelesSolarEvents(on: date))
        let sunset = try XCTUnwrap(events.sunset)
        let civilDusk = try XCTUnwrap(events.civilDusk)
        let eventDate = sunset.addingTimeInterval(civilDusk.timeIntervalSince(sunset) / 2.0)

        let result = SolarTwilight.twilightResult(at: eventDate, solarEvents: events)
        XCTAssertEqual(result.phase, .eveningCivilTwilight)
        XCTAssertEqual(try XCTUnwrap(result.percent), 0.5, accuracy: 0.0001)
    }

    func testTwilightResultAtCivilDawnIsMorningTwilightZeroPercent() throws {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = makeDate(year: 2026, month: 6, day: 7, hour: 12, timeZone: timeZone)
        let events = try XCTUnwrap(losAngelesSolarEvents(on: date))
        let civilDawn = try XCTUnwrap(events.civilDawn)

        let result = SolarTwilight.twilightResult(at: civilDawn, solarEvents: events)
        XCTAssertEqual(result.phase, .morningCivilTwilight)
        XCTAssertEqual(try XCTUnwrap(result.percent), 0.0, accuracy: 0.0001)
    }

    func testTwilightResultAtSunriseIsNone() throws {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = makeDate(year: 2026, month: 6, day: 7, hour: 12, timeZone: timeZone)
        let events = try XCTUnwrap(losAngelesSolarEvents(on: date))
        let sunrise = try XCTUnwrap(events.sunrise)

        let result = SolarTwilight.twilightResult(at: sunrise, solarEvents: events)
        XCTAssertEqual(result.phase, .none)
        XCTAssertNil(result.percent)
    }

    func testTwilightResultAtSunsetIsNone() throws {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = makeDate(year: 2026, month: 6, day: 7, hour: 12, timeZone: timeZone)
        let events = try XCTUnwrap(losAngelesSolarEvents(on: date))
        let sunset = try XCTUnwrap(events.sunset)

        let result = SolarTwilight.twilightResult(at: sunset, solarEvents: events)
        XCTAssertEqual(result.phase, .none)
        XCTAssertNil(result.percent)
    }

    func testTwilightResultAtCivilDuskIsEveningTwilightOnePercent() throws {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = makeDate(year: 2026, month: 6, day: 7, hour: 12, timeZone: timeZone)
        let events = try XCTUnwrap(losAngelesSolarEvents(on: date))
        let civilDusk = try XCTUnwrap(events.civilDusk)

        let result = SolarTwilight.twilightResult(at: civilDusk, solarEvents: events)
        XCTAssertEqual(result.phase, .eveningCivilTwilight)
        XCTAssertEqual(try XCTUnwrap(result.percent), 1.0, accuracy: 0.0001)
    }

    func testSolarNoonIsMidpointBetweenSunriseAndSunset() throws {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = makeDate(year: 2026, month: 6, day: 7, hour: 12, timeZone: timeZone)
        let events = try XCTUnwrap(losAngelesSolarEvents(on: date))
        let sunrise = try XCTUnwrap(events.sunrise)
        let sunset = try XCTUnwrap(events.sunset)
        let solarNoon = try XCTUnwrap(
            SolarTwilight.solarNoon(
                for: date,
                latitude: 33.8403,
                longitude: -118.0037,
                timeZone: timeZone
            )
        )

        let expectedMidpoint = sunrise.addingTimeInterval(sunset.timeIntervalSince(sunrise) / 2.0)
        XCTAssertEqual(solarNoon.timeIntervalSince(expectedMidpoint), 0.0, accuracy: 0.5)
        XCTAssertGreaterThan(solarNoon.timeIntervalSince(sunrise), 0)
        XCTAssertLessThan(solarNoon.timeIntervalSince(sunset), 0)
    }

    func testSolarPeriodResultClassifiesMorningDayEveningAndNightSegments() throws {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = makeDate(year: 2026, month: 6, day: 7, hour: 12, timeZone: timeZone)
        let events = try XCTUnwrap(losAngelesSolarEvents(on: date))
        let civilDawn = try XCTUnwrap(events.civilDawn)
        let sunrise = try XCTUnwrap(events.sunrise)
        let solarMidday = try XCTUnwrap(
            SolarTwilight.solarNoon(
                for: date,
                latitude: 33.8403,
                longitude: -118.0037,
                timeZone: timeZone
            )
        )
        let sunset = try XCTUnwrap(events.sunset)
        let civilDusk = try XCTUnwrap(events.civilDusk)
        let localMidnight = makeDate(year: 2026, month: 6, day: 7, hour: 0, timeZone: timeZone)
        let nextLocalMidnight = makeDate(year: 2026, month: 6, day: 8, hour: 0, timeZone: timeZone)

        let morningHalfway = civilDawn.addingTimeInterval(sunrise.timeIntervalSince(civilDawn) / 2.0)
        let dayQuarter = sunrise.addingTimeInterval(solarMidday.timeIntervalSince(sunrise) / 2.0)
        let dayThreeQuarter = solarMidday.addingTimeInterval(sunset.timeIntervalSince(solarMidday) / 2.0)
        let eveningHalfway = sunset.addingTimeInterval(civilDusk.timeIntervalSince(sunset) / 2.0)
        let nightBeforeHalfway = civilDusk.addingTimeInterval(nextLocalMidnight.timeIntervalSince(civilDusk) / 2.0)
        let nightAfterHalfway = localMidnight.addingTimeInterval(civilDawn.timeIntervalSince(localMidnight) / 2.0)

        XCTAssertEqual(
            SolarTwilight.solarPeriodResult(at: civilDawn, latitude: 33.8403, longitude: -118.0037, timeZone: timeZone),
            SolarPeriodResult(period: .morningCivilTwilight, percent: 0.0)
        )
        XCTAssertEqual(
            SolarTwilight.solarPeriodResult(at: morningHalfway, latitude: 33.8403, longitude: -118.0037, timeZone: timeZone).period,
            .morningCivilTwilight
        )
        XCTAssertEqual(
            try XCTUnwrap(SolarTwilight.solarPeriodResult(at: morningHalfway, latitude: 33.8403, longitude: -118.0037, timeZone: timeZone).percent),
            0.5,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SolarTwilight.solarPeriodResult(at: sunrise, latitude: 33.8403, longitude: -118.0037, timeZone: timeZone),
            SolarPeriodResult(period: .day, percent: 0.0)
        )
        XCTAssertEqual(
            SolarTwilight.solarPeriodResult(at: dayQuarter, latitude: 33.8403, longitude: -118.0037, timeZone: timeZone).period,
            .day
        )
        XCTAssertEqual(
            try XCTUnwrap(SolarTwilight.solarPeriodResult(at: dayQuarter, latitude: 33.8403, longitude: -118.0037, timeZone: timeZone).percent),
            0.25,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SolarTwilight.solarPeriodResult(at: solarMidday, latitude: 33.8403, longitude: -118.0037, timeZone: timeZone),
            SolarPeriodResult(period: .day, percent: 0.5)
        )
        XCTAssertEqual(
            SolarTwilight.solarPeriodResult(at: dayThreeQuarter, latitude: 33.8403, longitude: -118.0037, timeZone: timeZone).period,
            .day
        )
        XCTAssertEqual(
            try XCTUnwrap(SolarTwilight.solarPeriodResult(at: dayThreeQuarter, latitude: 33.8403, longitude: -118.0037, timeZone: timeZone).percent),
            0.75,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SolarTwilight.solarPeriodResult(at: sunset, latitude: 33.8403, longitude: -118.0037, timeZone: timeZone),
            SolarPeriodResult(period: .day, percent: 1.0)
        )
        XCTAssertEqual(
            SolarTwilight.solarPeriodResult(at: eveningHalfway, latitude: 33.8403, longitude: -118.0037, timeZone: timeZone).period,
            .eveningCivilTwilight
        )
        XCTAssertEqual(
            try XCTUnwrap(SolarTwilight.solarPeriodResult(at: eveningHalfway, latitude: 33.8403, longitude: -118.0037, timeZone: timeZone).percent),
            0.5,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SolarTwilight.solarPeriodResult(at: civilDusk, latitude: 33.8403, longitude: -118.0037, timeZone: timeZone),
            SolarPeriodResult(period: .eveningCivilTwilight, percent: 1.0)
        )
        XCTAssertEqual(
            SolarTwilight.solarPeriodResult(at: nightBeforeHalfway, latitude: 33.8403, longitude: -118.0037, timeZone: timeZone).period,
            .nightBeforeMidnight
        )
        XCTAssertEqual(
            try XCTUnwrap(SolarTwilight.solarPeriodResult(at: nightBeforeHalfway, latitude: 33.8403, longitude: -118.0037, timeZone: timeZone).percent),
            0.5,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SolarTwilight.solarPeriodResult(at: localMidnight, latitude: 33.8403, longitude: -118.0037, timeZone: timeZone),
            SolarPeriodResult(period: .nightAfterMidnight, percent: 0.0)
        )
        XCTAssertEqual(
            SolarTwilight.solarPeriodResult(at: nightAfterHalfway, latitude: 33.8403, longitude: -118.0037, timeZone: timeZone).period,
            .nightAfterMidnight
        )
        XCTAssertEqual(
            try XCTUnwrap(SolarTwilight.solarPeriodResult(at: nightAfterHalfway, latitude: 33.8403, longitude: -118.0037, timeZone: timeZone).percent),
            0.5,
            accuracy: 0.0001
        )
    }

    func testTimeOfDayColorResolverUsesMorningTwilightGradientAnchors() {
        let resolver = TimeOfDayColorResolver()
        let date = makeDate(
            year: 2026,
            month: 6,
            day: 7,
            hour: 6,
            timeZone: TimeZone(identifier: "America/Los_Angeles")!
        )

        XCTAssertEqual(
            resolver.color(for: makeDetail(date: date, twilightPhase: .morningCivilTwilight, twilightPercent: 0.0)),
            TimeOfDayBaseColors.endOfNight
        )
        XCTAssertEqual(
            resolver.color(for: makeDetail(date: date, twilightPhase: .morningCivilTwilight, twilightPercent: 0.5)),
            TimeOfDayBaseColors.morningTwilight
        )
        XCTAssertEqual(
            resolver.color(for: makeDetail(date: date, twilightPhase: .morningCivilTwilight, twilightPercent: 1.0)),
            TimeOfDayBaseColors.beginningOfDay
        )
    }

    func testTimeOfDayColorResolverUsesEveningTwilightGradientAnchors() {
        let resolver = TimeOfDayColorResolver()
        let date = makeDate(
            year: 2026,
            month: 6,
            day: 7,
            hour: 18,
            timeZone: TimeZone(identifier: "America/Los_Angeles")!
        )

        XCTAssertEqual(
            resolver.color(for: makeDetail(date: date, twilightPhase: .eveningCivilTwilight, twilightPercent: 0.0)),
            TimeOfDayBaseColors.endOfDay
        )
        XCTAssertEqual(
            resolver.color(for: makeDetail(date: date, twilightPhase: .eveningCivilTwilight, twilightPercent: 0.5)),
            TimeOfDayBaseColors.eveningTwilight
        )
        XCTAssertEqual(
            resolver.color(for: makeDetail(date: date, twilightPhase: .eveningCivilTwilight, twilightPercent: 1.0)),
            TimeOfDayBaseColors.beginningOfNight
        )
    }

    func testTimeOfDayColorResolverUsesDayGradientAnchors() {
        let resolver = TimeOfDayColorResolver()
        let date = makeDate(
            year: 2026,
            month: 6,
            day: 7,
            hour: 12,
            timeZone: TimeZone(identifier: "America/Los_Angeles")!
        )

        XCTAssertEqual(
            resolver.color(for: makeDetail(date: date, solarPeriod: .day, solarPeriodPercent: 0.0)),
            TimeOfDayBaseColors.beginningOfDay
        )
        XCTAssertEqual(
            resolver.color(for: makeDetail(date: date, solarPeriod: .day, solarPeriodPercent: 0.5)),
            TimeOfDayBaseColors.midday
        )
        XCTAssertEqual(
            resolver.color(for: makeDetail(date: date, solarPeriod: .day, solarPeriodPercent: 1.0)),
            TimeOfDayBaseColors.endOfDay
        )
    }

    func testTimeOfDayColorResolverUsesNightGradientAnchors() {
        let resolver = TimeOfDayColorResolver()
        let date = makeDate(
            year: 2026,
            month: 6,
            day: 7,
            hour: 0,
            timeZone: TimeZone(identifier: "America/Los_Angeles")!
        )

        XCTAssertEqual(
            resolver.color(for: makeDetail(date: date, solarPeriod: .nightBeforeMidnight, solarPeriodPercent: 0.0)),
            TimeOfDayBaseColors.beginningOfNight
        )
        XCTAssertEqual(
            resolver.color(for: makeDetail(date: date, solarPeriod: .nightBeforeMidnight, solarPeriodPercent: 0.5)),
            TimeOfDayBaseColors.midnight
        )
        XCTAssertEqual(
            resolver.color(for: makeDetail(date: date, solarPeriod: .nightBeforeMidnight, solarPeriodPercent: 1.0)),
            TimeOfDayBaseColors.beginningOfNight
        )
    }

    func testTimeOfDayColorResolverFallsBackToTwilightColorWhenPercentIsMissing() {
        let resolver = TimeOfDayColorResolver()
        let date = makeDate(
            year: 2026,
            month: 6,
            day: 7,
            hour: 6,
            timeZone: TimeZone(identifier: "America/Los_Angeles")!
        )

        XCTAssertEqual(
            resolver.color(for: makeDetail(date: date, twilightPhase: .morningCivilTwilight, twilightPercent: nil)),
            TimeOfDayBaseColors.morningTwilight
        )
        XCTAssertEqual(
            resolver.color(for: makeDetail(date: date, twilightPhase: .eveningCivilTwilight, twilightPercent: nil)),
            TimeOfDayBaseColors.eveningTwilight
        )
    }

    func testTimeOfDayColorResolverFallsBackToUnknownForNonePhase() throws {
        let resolver = TimeOfDayColorResolver()
        XCTAssertEqual(
            resolver.color(for: makeDetail(date: makeDate(year: 2026, month: 6, day: 7, hour: 12, timeZone: TimeZone(identifier: "America/Los_Angeles")!), solarPeriod: .unknown)),
            TimeOfDayBaseColors.unknown
        )
        XCTAssertEqual(
            resolver.color(for: makeDetail(date: makeDate(year: 2026, month: 6, day: 7, hour: 0, timeZone: TimeZone(identifier: "America/Los_Angeles")!), solarPeriod: .unknown)),
            TimeOfDayBaseColors.unknown
        )
    }

    func testTimeOfDayColorResolverFallsBackToUnknownForInvalidTimezone() {
        let resolver = TimeOfDayColorResolver()
        let date = makeDate(
            year: 2026,
            month: 6,
            day: 7,
            hour: 12,
            timeZone: TimeZone(identifier: "America/Los_Angeles")!
        )

        XCTAssertEqual(
            resolver.color(for: makeDetail(date: date, timeZoneIdentifier: "Not/AZone", solarPeriod: .unknown)),
            TimeOfDayBaseColors.unknown
        )
    }

    func testTimeOfDayColorResolverFormatsTwilightAndDayLabels() throws {
        let resolver = TimeOfDayColorResolver()
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = makeDate(year: 2026, month: 6, day: 7, hour: 12, timeZone: timeZone)
        let solarEvents = try XCTUnwrap(losAngelesSolarEvents(on: date))
        let sunrise = try XCTUnwrap(solarEvents.sunrise)
        let sunset = try XCTUnwrap(solarEvents.sunset)
        let civilDawn = try XCTUnwrap(solarEvents.civilDawn)
        let civilDusk = try XCTUnwrap(solarEvents.civilDusk)
        let morningHalfway = civilDawn.addingTimeInterval(sunrise.timeIntervalSince(civilDawn) / 2.0)
        let eveningHalfway = sunset.addingTimeInterval(civilDusk.timeIntervalSince(sunset) / 2.0)
        let daylightDate = sunrise.addingTimeInterval(3 * 3_600)
        let nightDate = civilDawn.addingTimeInterval(-3_600)

        XCTAssertEqual(
            resolver.displayText(for: makeDetail(date: morningHalfway, twilightPhase: .morningCivilTwilight, twilightPercent: 0.2)),
            "Morning Twilight - 20%"
        )
        XCTAssertEqual(
            resolver.displayText(for: makeDetail(date: eveningHalfway, twilightPhase: .eveningCivilTwilight, twilightPercent: 0.74)),
            "Evening Twilight - 74%"
        )
        XCTAssertEqual(
            resolver.displayText(for: makeDetail(date: daylightDate, solarPeriod: .day)),
            "Day"
        )
        XCTAssertEqual(
            resolver.displayText(for: makeDetail(date: nightDate, solarPeriod: .nightBeforeMidnight)),
            "Night"
        )
        XCTAssertEqual(
            resolver.displayText(for: makeDetail(date: daylightDate, timeZoneIdentifier: "Not/AZone", solarPeriod: .unknown)),
            "Unknown"
        )
    }

    func testTwilightResultIgnoresInvalidCoordinates() {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = makeDate(year: 2026, month: 6, day: 7, hour: 12, timeZone: timeZone)
        let result = SolarTwilight.twilightResult(at: date, latitude: 120, longitude: 0, timeZone: timeZone)
        XCTAssertEqual(result.phase, .none)
        XCTAssertNil(result.percent)
        let solarResult = SolarTwilight.solarPeriodResult(at: date, latitude: 120, longitude: 0, timeZone: timeZone)
        XCTAssertEqual(solarResult.period, .unknown)
        XCTAssertNil(solarResult.percent)
    }

    func testTwilightIsStoredWhenLocationHasValidTimeZone() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let geolocationID = try store.saveGeolocation(
            Geolocation(
                latitude: 33.8403,
                longitude: -118.0037,
                timeZoneIdentifier: "America/Los_Angeles",
                name: "Buena Park"
            )
        )
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = makeDate(year: 2026, month: 6, day: 7, hour: 12, timeZone: timeZone)
        let events = try XCTUnwrap(losAngelesSolarEvents(on: date))
        let civilDawn = try XCTUnwrap(events.civilDawn)
        let sunrise = try XCTUnwrap(events.sunrise)
        let eventDate = civilDawn.addingTimeInterval(sunrise.timeIntervalSince(civilDawn) / 2.0)

        let eventID = try store.saveEvent(
            LocationEvent(
                latitude: 33.8403,
                longitude: -118.0037,
                horizontalAccuracy: 12,
                timestamp: eventDate,
                localizedDate: TravelsDateTools.localizedDayString(for: eventDate, timeZoneIdentifier: "America/Los_Angeles"),
                source: .locationServices,
                geolocationID: geolocationID
            )
        )

        let saved = try store.allEvents().first(where: { $0.event.id == eventID })
        XCTAssertEqual(saved?.event.solarPeriod, .morningCivilTwilight)
        XCTAssertEqual(try XCTUnwrap(saved?.event.solarPeriodPercent), 0.5, accuracy: 0.0001)
        XCTAssertNotNil(saved?.event.solarPeriodCalculatedAt)
        XCTAssertEqual(saved?.event.twilightPhase, .morningCivilTwilight)
        XCTAssertEqual(try XCTUnwrap(saved?.event.twilightPercent), 0.5, accuracy: 0.0001)
    }

    func testTwilightIsNoneWhenGeolocationTimeZoneIsMissingOrInvalid() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let invalidGeoID = try store.saveGeolocation(
            Geolocation(
                latitude: 33.8403,
                longitude: -118.0037,
                timeZoneIdentifier: "Not/AZone",
                name: "Invalid Zone"
            )
        )
        let eventDate = makeDate(
            year: 2026,
            month: 6,
            day: 7,
            hour: 12,
            timeZone: TimeZone(identifier: "America/Los_Angeles")!
        )
        let eventID = try store.saveEvent(
            LocationEvent(
                latitude: 33.8403,
                longitude: -118.0037,
                horizontalAccuracy: 12,
                timestamp: eventDate,
                localizedDate: TravelsDateTools.localizedDayString(for: eventDate, timeZoneIdentifier: "America/Los_Angeles"),
                source: .locationServices,
                geolocationID: invalidGeoID
            )
        )

        let saved = try store.allEvents().first(where: { $0.event.id == eventID })
        XCTAssertEqual(saved?.event.solarPeriod, .unknown)
        XCTAssertNil(saved?.event.solarPeriodPercent)
        XCTAssertNotNil(saved?.event.solarPeriodCalculatedAt)
        XCTAssertEqual(try XCTUnwrap(saved?.event.twilightPhase), .none)
        XCTAssertNil(saved?.event.twilightPercent)
    }

    func testTwilightIsNoneForPolarEdgeCases() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let geolocationID = try store.saveGeolocation(
            Geolocation(
                latitude: 90.0,
                longitude: 0.0,
                timeZoneIdentifier: "UTC",
                name: "North Pole"
            )
        )
        let timeZone = TimeZone(identifier: "UTC")!
        let eventDate = makeDate(year: 2026, month: 6, day: 7, hour: 12, timeZone: timeZone)
        let eventID = try store.saveEvent(
            LocationEvent(
                latitude: 90.0,
                longitude: 0.0,
                horizontalAccuracy: 12,
                timestamp: eventDate,
                localizedDate: TravelsDateTools.localizedDayString(for: eventDate, timeZoneIdentifier: "UTC"),
                source: .locationServices,
                geolocationID: geolocationID
            )
        )

        let saved = try store.allEvents().first(where: { $0.event.id == eventID })
        XCTAssertEqual(saved?.event.solarPeriod, .unknown)
        XCTAssertNil(saved?.event.solarPeriodPercent)
        XCTAssertNotNil(saved?.event.solarPeriodCalculatedAt)
        XCTAssertEqual(try XCTUnwrap(saved?.event.twilightPhase), .none)
        XCTAssertNil(saved?.event.twilightPercent)
    }

    func testDemoDayDoesNotPullInPreviousDayContext() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let previousDayTail = makeDate(year: 2026, month: 6, day: 7, hour: 23, minute: 50, timeZone: timeZone)
        let demoDayStart = makeDate(year: 2026, month: 6, day: 8, hour: 0, minute: 10, timeZone: timeZone)

        _ = try store.saveEvent(
            LocationEvent(
                latitude: 33.8403,
                longitude: -118.0037,
                timestamp: previousDayTail,
                localizedDate: TravelsDateTools.localizedDayString(for: previousDayTail, timeZoneIdentifier: timeZone.identifier),
                source: .locationServices,
                note: "Previous day tail"
            )
        )
        _ = try store.saveEvent(
            LocationEvent(
                latitude: 33.8403,
                longitude: -118.0037,
                timestamp: demoDayStart,
                localizedDate: TravelsDateTools.localizedDayString(for: demoDayStart, timeZoneIdentifier: timeZone.identifier),
                source: .simulated,
                note: "Demo day start",
                isDemo: true
            ),
            isDemo: true
        )

        let dayEvents = try store.events(
            on: demoDayStart,
            includePreviousDayContext: true,
            includeDemo: true
        )

        XCTAssertEqual(dayEvents.map(\.event.note), ["Demo day start"])
    }

    func testMigrationAddsTwilightCalculatedAtWithoutDestroyingExistingEvents() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        try createLegacyEventsDatabase(at: url)
        let store = try TravelsStore(url: url)
        let inspector = try SQLiteDatabase(path: url.path)
        let columns = try inspector.query("PRAGMA table_info(events)")
        XCTAssertTrue(columns.contains { $0["name"]?.string == "solar_period" })
        XCTAssertTrue(columns.contains { $0["name"]?.string == "solar_period_percent" })
        XCTAssertTrue(columns.contains { $0["name"]?.string == "solar_period_calculated_at" })
        XCTAssertTrue(columns.contains { $0["name"]?.string == "twilight_calculated_at" })

        let saved = try store.allEvents().first
        XCTAssertEqual(saved?.event.note, "legacy note")
        XCTAssertEqual(saved?.event.solarPeriod, .unknown)
        XCTAssertNil(saved?.event.solarPeriodPercent)
        XCTAssertNil(saved?.event.solarPeriodCalculatedAt)
        XCTAssertNil(saved?.event.twilightCalculatedAt)
        XCTAssertEqual(try store.eventCount(), 1)
    }

    func testNewTwilightEventSetsTwilightCalculatedAt() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let geolocationID = try store.saveGeolocation(
            Geolocation(
                latitude: 33.8403,
                longitude: -118.0037,
                timeZoneIdentifier: "America/Los_Angeles",
                name: "Buena Park"
            )
        )
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = makeDate(year: 2026, month: 6, day: 7, hour: 12, timeZone: timeZone)
        let events = try XCTUnwrap(losAngelesSolarEvents(on: date))
        let civilDawn = try XCTUnwrap(events.civilDawn)
        let sunrise = try XCTUnwrap(events.sunrise)
        let eventDate = civilDawn.addingTimeInterval(sunrise.timeIntervalSince(civilDawn) / 2.0)

        _ = try store.saveEvent(
            LocationEvent(
                latitude: 33.8403,
                longitude: -118.0037,
                horizontalAccuracy: 12,
                timestamp: eventDate,
                localizedDate: TravelsDateTools.localizedDayString(for: eventDate, timeZoneIdentifier: "America/Los_Angeles"),
                source: .locationServices,
                geolocationID: geolocationID
            )
        )

        let saved = try XCTUnwrap(try store.allEvents().first)
        XCTAssertEqual(saved.event.solarPeriod, .morningCivilTwilight)
        XCTAssertEqual(try XCTUnwrap(saved.event.solarPeriodPercent), 0.5, accuracy: 0.0001)
        XCTAssertNotNil(saved.event.solarPeriodCalculatedAt)
        XCTAssertEqual(saved.event.twilightPhase, .morningCivilTwilight)
        XCTAssertEqual(try XCTUnwrap(saved.event.twilightPercent), 0.5, accuracy: 0.0001)
        XCTAssertNotNil(saved.event.twilightCalculatedAt)
    }

    func testNonTwilightEventStillSetsTwilightCalculatedAt() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let geolocationID = try store.saveGeolocation(
            Geolocation(
                latitude: 33.8403,
                longitude: -118.0037,
                timeZoneIdentifier: "America/Los_Angeles",
                name: "Buena Park"
            )
        )
        let eventDate = makeDate(
            year: 2026,
            month: 6,
            day: 7,
            hour: 12,
            timeZone: TimeZone(identifier: "America/Los_Angeles")!
        )

        _ = try store.saveEvent(
            LocationEvent(
                latitude: 33.8403,
                longitude: -118.0037,
                horizontalAccuracy: 12,
                timestamp: eventDate,
                localizedDate: TravelsDateTools.localizedDayString(for: eventDate, timeZoneIdentifier: "America/Los_Angeles"),
                source: .locationServices,
                geolocationID: geolocationID
            )
        )

        let saved = try XCTUnwrap(try store.allEvents().first)
        XCTAssertEqual(saved.event.solarPeriod, .day)
        XCTAssertNotNil(saved.event.solarPeriodCalculatedAt)
        XCTAssertEqual(try XCTUnwrap(saved.event.solarPeriodPercent), 0.5, accuracy: 0.0001)
        XCTAssertEqual(saved.event.twilightPhase, .none)
        XCTAssertNil(saved.event.twilightPercent)
        XCTAssertNotNil(saved.event.twilightCalculatedAt)
    }

    func testAttachingGeolocationRecalculatesTwilightForEveningTwilightEvent() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let geolocationID = try store.saveGeolocation(
            Geolocation(
                latitude: 33.8403,
                longitude: -118.0037,
                timeZoneIdentifier: "America/Los_Angeles",
                name: "Buena Park"
            )
        )
        let eventDate = makeDate(
            year: 2026,
            month: 6,
            day: 7,
            hour: 20,
            minute: 10,
            timeZone: TimeZone(identifier: "America/Los_Angeles")!
        )

        let eventID = try store.saveEvent(
            LocationEvent(
                latitude: 33.8403,
                longitude: -118.0037,
                horizontalAccuracy: 12,
                timestamp: eventDate,
                localizedDate: TravelsDateTools.localizedDayString(for: eventDate, timeZoneIdentifier: "America/Los_Angeles"),
                source: .locationServices
            )
        )

        try store.attachGeolocation(geolocationID, toEvent: eventID)

        let solarEvents = try XCTUnwrap(losAngelesSolarEvents(on: eventDate))
        let sunset = try XCTUnwrap(solarEvents.sunset)
        let civilDusk = try XCTUnwrap(solarEvents.civilDusk)
        let expectedPercent = eventDate.timeIntervalSince(sunset) / civilDusk.timeIntervalSince(sunset)

        let saved = try XCTUnwrap(try store.allEvents().first)
        XCTAssertEqual(saved.event.solarPeriod, .eveningCivilTwilight)
        XCTAssertNotNil(saved.event.solarPeriodCalculatedAt)
        XCTAssertEqual(try XCTUnwrap(saved.event.solarPeriodPercent), expectedPercent, accuracy: 0.0001)
        XCTAssertEqual(saved.event.twilightPhase, .eveningCivilTwilight)
        XCTAssertNotNil(saved.event.twilightCalculatedAt)
        XCTAssertEqual(try XCTUnwrap(saved.event.twilightPercent), expectedPercent, accuracy: 0.0001)
    }

    func testInvalidTwilightInputsStillSetTwilightCalculatedAt() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let geolocationID = try store.saveGeolocation(
            Geolocation(
                latitude: 33.8403,
                longitude: -118.0037,
                timeZoneIdentifier: "America/Los_Angeles",
                name: "Buena Park"
            )
        )
        let eventDate = makeDate(
            year: 2026,
            month: 6,
            day: 7,
            hour: 12,
            timeZone: TimeZone(identifier: "America/Los_Angeles")!
        )

        _ = try store.saveEvent(
            LocationEvent(
                latitude: 120,
                longitude: -118.0037,
                horizontalAccuracy: 12,
                timestamp: eventDate,
                localizedDate: TravelsDateTools.localizedDayString(for: eventDate, timeZoneIdentifier: "America/Los_Angeles"),
                source: .locationServices,
                geolocationID: geolocationID
            )
        )

        let saved = try XCTUnwrap(try store.allEvents().first)
        XCTAssertEqual(saved.event.solarPeriod, .unknown)
        XCTAssertNil(saved.event.solarPeriodPercent)
        XCTAssertNotNil(saved.event.solarPeriodCalculatedAt)
        XCTAssertEqual(saved.event.twilightPhase, .none)
        XCTAssertNil(saved.event.twilightPercent)
        XCTAssertNotNil(saved.event.twilightCalculatedAt)
    }

    func testFetchLocationEventsMissingTwilightReturnsOnlyNullRows() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let older = try store.saveEvent(
            LocationEvent(
                latitude: 1,
                longitude: 1,
                timestamp: Date(timeIntervalSinceReferenceDate: 1_000),
                localizedDate: "2001-01-01",
                source: .locationServices
            )
        )
        let middle = try store.saveEvent(
            LocationEvent(
                latitude: 2,
                longitude: 2,
                timestamp: Date(timeIntervalSinceReferenceDate: 2_000),
                localizedDate: "2001-01-01",
                source: .locationServices
            )
        )
        let newer = try store.saveEvent(
            LocationEvent(
                latitude: 3,
                longitude: 3,
                timestamp: Date(timeIntervalSinceReferenceDate: 3_000),
                localizedDate: "2001-01-01",
                source: .locationServices
            )
        )

        let inspector = try SQLiteDatabase(path: url.path)
        try inspector.execute("UPDATE events SET solar_period_calculated_at = NULL WHERE id IN (?, ?)", parameters: [.integer(older), .integer(newer)])

        let missing = try store.fetchLocationEventsMissingTwilight(limit: 10)
        XCTAssertEqual(missing.map(\.id), [newer, older])
        XCTAssertTrue(missing.allSatisfy { $0.twilightCalculatedAt == nil })
        let solarMissing = try store.fetchLocationEventsMissingSolarPeriod(limit: 10)
        XCTAssertEqual(solarMissing.map(\.id), [newer, older])
        XCTAssertTrue(solarMissing.allSatisfy { $0.solarPeriodCalculatedAt == nil })
        XCTAssertEqual(missing.count, 2)
        XCTAssertFalse(missing.contains(where: { $0.id == middle }))
    }

    func testFetchLocationEventsMissingTwilightRespectsLimit() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let first = try store.saveEvent(
            LocationEvent(
                latitude: 1,
                longitude: 1,
                timestamp: Date(timeIntervalSinceReferenceDate: 1_000),
                localizedDate: "2001-01-01",
                source: .locationServices
            )
        )
        let second = try store.saveEvent(
            LocationEvent(
                latitude: 2,
                longitude: 2,
                timestamp: Date(timeIntervalSinceReferenceDate: 2_000),
                localizedDate: "2001-01-01",
                source: .locationServices
            )
        )
        let third = try store.saveEvent(
            LocationEvent(
                latitude: 3,
                longitude: 3,
                timestamp: Date(timeIntervalSinceReferenceDate: 3_000),
                localizedDate: "2001-01-01",
                source: .locationServices
            )
        )

        let inspector = try SQLiteDatabase(path: url.path)
        try inspector.execute("UPDATE events SET solar_period_calculated_at = NULL")
        let missing = try store.fetchLocationEventsMissingTwilight(limit: 2)
        XCTAssertEqual(missing.count, 2)
        XCTAssertEqual(missing.map(\.id), [third, second])
        XCTAssertFalse(missing.contains(where: { $0.id == first }))
        let solarMissing = try store.fetchLocationEventsMissingSolarPeriod(limit: 2)
        XCTAssertEqual(solarMissing.map(\.id), [third, second])
    }

    func testFetchLocationEventsMissingTwilightReturnsNewestFirst() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let oldest = try store.saveEvent(
            LocationEvent(
                latitude: 1,
                longitude: 1,
                timestamp: Date(timeIntervalSinceReferenceDate: 1_000),
                localizedDate: "2001-01-01",
                source: .locationServices
            )
        )
        let middle = try store.saveEvent(
            LocationEvent(
                latitude: 2,
                longitude: 2,
                timestamp: Date(timeIntervalSinceReferenceDate: 2_000),
                localizedDate: "2001-01-01",
                source: .locationServices
            )
        )
        let newest = try store.saveEvent(
            LocationEvent(
                latitude: 3,
                longitude: 3,
                timestamp: Date(timeIntervalSinceReferenceDate: 3_000),
                localizedDate: "2001-01-01",
                source: .locationServices
            )
        )

        let inspector = try SQLiteDatabase(path: url.path)
        try inspector.execute("UPDATE events SET twilight_calculated_at = NULL")

        let missing = try store.fetchLocationEventsMissingTwilight(limit: 10)
        XCTAssertEqual(missing.map(\.id), [newest, middle, oldest])
    }

    func testDatabaseHealthReportIsHealthyForFreshDatabase() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let report = try store.databaseHealthReport()

        XCTAssertTrue(report.isHealthy)
        XCTAssertEqual(report.issues, ["ok"])
    }

    func testDatabaseHealthReportAndRepairHandleForeignKeyViolations() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = root.appendingPathComponent("Travels.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try TravelsStore(url: url)
        let inspector = try SQLiteDatabase(path: url.path)
        try inspector.execute("PRAGMA foreign_keys = OFF")
        try inspector.execute(
            """
            INSERT INTO events (
                latitude, longitude, horizontalAccuracy, verticalAccuracy, altitude, course, speed,
                timestamp, source, geolocationID, note, tags, externalReference, photoFilename, isDemo
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            parameters: [
                .real(33.0),
                .real(-118.0),
                .real(10),
                .real(10),
                .real(0),
                .real(0),
                .real(0),
                .real(1_000),
                .integer(Int64(EventSource.locationServices.rawValue)),
                .integer(999),
                .text("corrupt"),
                .text(""),
                .text("corrupt"),
                .text(""),
                .integer(0)
            ]
        )

        let report = try store.databaseHealthReport()
        XCTAssertFalse(report.isHealthy)
        XCTAssertTrue(report.issues.contains { $0.lowercased().contains("foreign_key") })

        let repairRoot = root.appendingPathComponent("repairs", isDirectory: true)
        let outcome = try XCTUnwrap(try store.validateAndRepairIfNeeded(quarantineRoot: repairRoot))
        XCTAssertNotNil(outcome.backupDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outcome.backupDirectory!.path))

        let repairedReport = try store.databaseHealthReport()
        XCTAssertTrue(repairedReport.isHealthy)
        XCTAssertEqual(try store.eventCount(), 0)
    }

    func testRebuildTwilightCalculationsRejectsInvalidTimeZone() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let eventID = try store.saveEvent(
            LocationEvent(
                latitude: 33.0,
                longitude: -118.0,
                timestamp: Date(timeIntervalSinceReferenceDate: 3_000),
                localizedDate: "2001-01-01",
                source: .locationServices
            )
        )
        let inspector = try SQLiteDatabase(path: url.path)
        try inspector.execute("UPDATE events SET solar_period_calculated_at = NULL WHERE id = ?", parameters: [.integer(eventID)])

        XCTAssertThrowsError(try store.rebuildTwilightCalculations(timeZoneIdentifier: "Not/AZone")) { error in
            XCTAssertEqual(error as? TravelsError, .invalidTimeZoneIdentifier("Not/AZone"))
        }

        let saved = try XCTUnwrap(try store.allEvents().first(where: { $0.event.id == eventID }))
        XCTAssertNil(saved.event.solarPeriodCalculatedAt)
        XCTAssertNil(saved.event.twilightCalculatedAt)
    }

    func testRebuildTwilightCalculationsUsesSuppliedTimeZoneAndMarksEventsProcessed() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let middayID = try store.saveEvent(
            LocationEvent(
                latitude: 33.8403,
                longitude: -118.0037,
                timestamp: makeDate(year: 2026, month: 6, day: 7, hour: 12, timeZone: TimeZone(identifier: "UTC")!),
                localizedDate: "2026-06-07",
                source: .locationServices
            )
        )
        let eveningID = try store.saveEvent(
            LocationEvent(
                latitude: 33.8403,
                longitude: -118.0037,
                timestamp: makeDate(year: 2026, month: 6, day: 7, hour: 20, minute: 10, timeZone: TimeZone(identifier: "UTC")!),
                localizedDate: "2026-06-07",
                source: .locationServices
            )
        )
        let inspector = try SQLiteDatabase(path: url.path)
        try inspector.execute("UPDATE events SET solar_period_calculated_at = NULL, solar_period = 'unknown', solar_period_percent = NULL")

        let processedCount = try store.rebuildTwilightCalculations(timeZoneIdentifier: "America/Los_Angeles")
        XCTAssertEqual(processedCount, 2)

        let events = try store.allEvents()
        let midday = try XCTUnwrap(events.first(where: { $0.event.id == middayID }))
        let evening = try XCTUnwrap(events.first(where: { $0.event.id == eveningID }))

        XCTAssertNotNil(midday.event.solarPeriodCalculatedAt)
        XCTAssertEqual(midday.event.solarPeriod, .day)
        XCTAssertEqual(try XCTUnwrap(midday.event.solarPeriodPercent), 0.5, accuracy: 0.0001)
        XCTAssertNotNil(midday.event.twilightCalculatedAt)
        XCTAssertEqual(midday.event.twilightPhase, .none)
        XCTAssertNil(midday.event.twilightPercent)

        XCTAssertNotNil(evening.event.solarPeriodCalculatedAt)
        XCTAssertEqual(evening.event.solarPeriod, .eveningCivilTwilight)
        XCTAssertNotNil(evening.event.solarPeriodPercent)
        XCTAssertNotNil(evening.event.twilightCalculatedAt)
        XCTAssertEqual(evening.event.twilightPhase, .eveningCivilTwilight)
        XCTAssertNotNil(evening.event.twilightPercent)
    }

    func testRebuildTwilightCalculationsRecomputesPreviouslyUnknownEventsEvenWhenAlreadyProcessed() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let middayID = try store.saveEvent(
            LocationEvent(
                latitude: 33.8403,
                longitude: -118.0037,
                timestamp: makeDate(year: 2026, month: 6, day: 7, hour: 12, timeZone: TimeZone(identifier: "UTC")!),
                localizedDate: "2026-06-07",
                source: .locationServices
            )
        )

        let processedCount = try store.rebuildTwilightCalculations(timeZoneIdentifier: "America/Los_Angeles")
        XCTAssertEqual(processedCount, 1)

        let midday = try XCTUnwrap(try store.allEvents().first(where: { $0.event.id == middayID }))
        XCTAssertNotNil(midday.event.solarPeriodCalculatedAt)
        XCTAssertEqual(midday.event.solarPeriod, .day)
        XCTAssertEqual(try XCTUnwrap(midday.event.solarPeriodPercent), 0.5, accuracy: 0.0001)
    }

    func testGPXImportParsesTrackPoints() throws {
        let result = try GPXImporter.parse(url: fixtureURL("sample.gpx"))
        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.skippedInvalidPoints, 0)
        XCTAssertEqual(result.events[0].source, .imported)
        XCTAssertEqual(result.events[0].note, "Sample import")
        XCTAssertEqual(result.events[0].horizontalAccuracy, 12)
        XCTAssertEqual(result.events[0].speed, 1.2, accuracy: 0.0001)
        XCTAssertEqual(result.events[0].course, 90, accuracy: 0.0001)
        XCTAssertEqual(result.events[0].localizedDate, "2026-05-31")
        XCTAssertEqual(result.events[0].solarPeriod, .day)
        XCTAssertEqual(try XCTUnwrap(result.events[0].solarPeriodPercent), 0.5, accuracy: 0.0001)
        XCTAssertEqual(result.trackPoints.first?.geolocation?.timeZoneIdentifier, "America/Los_Angeles")
        XCTAssertEqual(result.trackPoints.first?.geolocation?.areasOfInterest, ["Apple Park"])
    }

    func testGPXImportParsesLegacyTrackPoints() throws {
        let legacyGPX = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Travels - life tracking" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <trkseg>
              <trkpt lat="37.331700" lon="-122.030100">
                <time>2026-05-31T12:00:00Z</time>
                <heading>180</heading>
                <speed>2.4</speed>
                <horizontalAccuracy>7</horizontalAccuracy>
                <timeZone>America/Los_Angeles</timeZone>
                <name>Legacy Apple Park</name>
                <locality>Cupertino</locality>
                <administrativeArea>California</administrativeArea>
                <country>United States</country>
                <areasOfInterest>One|||TRAVELS|||Two</areasOfInterest>
                <note>Legacy note</note>
              </trkpt>
            </trkseg>
          </trk>
        </gpx>
        """

        let result = try GPXImporter.parse(data: Data(legacyGPX.utf8))
        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.skippedInvalidPoints, 0)
        XCTAssertEqual(result.events[0].source, .imported)
        XCTAssertEqual(result.events[0].note, "Legacy note")
        XCTAssertEqual(result.events[0].horizontalAccuracy, 7)
        XCTAssertEqual(result.events[0].course, 180, accuracy: 0.0001)
        XCTAssertEqual(result.events[0].speed, 2.4, accuracy: 0.0001)
        XCTAssertEqual(result.trackPoints.first?.geolocation?.name, "Legacy Apple Park")
        XCTAssertEqual(result.trackPoints.first?.geolocation?.locality, "Cupertino")
        XCTAssertEqual(result.trackPoints.first?.geolocation?.administrativeArea, "California")
        XCTAssertEqual(result.trackPoints.first?.geolocation?.country, "United States")
        XCTAssertEqual(result.trackPoints.first?.geolocation?.areasOfInterest, ["One", "Two"])
    }

    func testGPXImportParsesLegacyReferenceDateTimestamps() throws {
        let legacyGPX = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Travels - life tracking" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <trkseg>
              <trkpt lat="37.331700" lon="-122.030100">
                <time>520537312.000111</time>
              </trkpt>
            </trkseg>
          </trk>
        </gpx>
        """

        let result = try GPXImporter.parse(data: Data(legacyGPX.utf8))
        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events[0].timestamp.timeIntervalSinceReferenceDate, 520537312.000111, accuracy: 0.000001)
    }

    func testGPXExtensionSpecDocumentExists() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: repositoryRootURL().appendingPathComponent("docs/gpx-extension-v1.md").path))
    }

    func testGPXImportParsesCanonicalMinimalFixture() throws {
        let result = try GPXImporter.parse(url: fixtureURL("gpx/travels-extension-v1-minimal.gpx"))
        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events.first?.source, .imported)
        XCTAssertNil(result.trackPoints.first?.geolocation)
    }

    func testGPXImportParsesCanonicalFullFixture() throws {
        let result = try GPXImporter.parse(url: fixtureURL("gpx/travels-extension-v1-full.gpx"))
        XCTAssertEqual(result.events.count, 1)
        let event = try XCTUnwrap(result.events.first)
        let geolocation = try XCTUnwrap(result.trackPoints.first?.geolocation)

        XCTAssertEqual(event.source, .imported)
        XCTAssertEqual(event.note, "Note with <angle> brackets & ampersands")
        XCTAssertEqual(event.horizontalAccuracy, 12)
        XCTAssertEqual(event.verticalAccuracy, 8)
        XCTAssertEqual(event.course, 90, accuracy: 0.0001)
        XCTAssertEqual(event.speed, 1.2, accuracy: 0.0001)
        XCTAssertEqual(event.localizedDate, "2026-05-31")
        XCTAssertEqual(event.tags, "Museum & art\nFood <travel>")
        XCTAssertEqual(event.externalReference, "sample-reference")
        XCTAssertEqual(event.photoFilename, "sample-photo.jpg")
        XCTAssertEqual(event.isDemo, true)
        XCTAssertEqual(event.solarPeriod, .day)
        XCTAssertEqual(try XCTUnwrap(event.solarPeriodPercent), 0.5, accuracy: 0.0001)
        XCTAssertEqual(geolocation.name, "Tom & Jerry Park")
        XCTAssertEqual(geolocation.timeZoneIdentifier, "America/Los_Angeles")
        XCTAssertEqual(geolocation.areasOfInterest, ["Apple Park", "Visitor Center"])
    }

    func testGPXImportParsesLegacyDirectFieldFixture() throws {
        let result = try GPXImporter.parse(url: fixtureURL("gpx/travels-legacy-direct-fields.gpx"))
        XCTAssertEqual(result.events.count, 1)
        let event = try XCTUnwrap(result.events.first)
        let geolocation = try XCTUnwrap(result.trackPoints.first?.geolocation)

        XCTAssertEqual(event.source, .imported)
        XCTAssertEqual(event.note, "Legacy note")
        XCTAssertEqual(event.horizontalAccuracy, 7)
        XCTAssertEqual(event.course, 180, accuracy: 0.0001)
        XCTAssertEqual(event.speed, 2.4, accuracy: 0.0001)
        XCTAssertEqual(event.tags, "legacy tag")
        XCTAssertEqual(event.solarPeriod, .day)
        XCTAssertEqual(try XCTUnwrap(event.solarPeriodPercent), 0.5, accuracy: 0.0001)
        XCTAssertEqual(geolocation.name, "Legacy Apple Park")
        XCTAssertEqual(geolocation.timeZoneIdentifier, "America/Los_Angeles")
        XCTAssertEqual(geolocation.areasOfInterest, ["One", "Two"])
    }

    func testGPXImportPrefersNamespacedValuesOverLegacyAliases() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Travels - life tracking" xmlns="http://www.topografix.com/GPX/1/1" xmlns:travels="https://github.com/dkrnet/travels-ios/gpx/extensions/1">
          <trk>
            <trkseg>
              <trkpt lat="37.3317" lon="-122.0301">
                <time>2026-05-31T12:00:00Z</time>
                <name>Legacy Name</name>
                <src>Manual</src>
                <horizontalAccuracy>99</horizontalAccuracy>
                <timeZone>America/New_York</timeZone>
                <tags>legacy tag</tags>
                <solarPeriod>night_before_midnight</solarPeriod>
                <extensions>
                  <travels:source>Imported</travels:source>
                  <travels:horizontalAccuracyMeters>12</travels:horizontalAccuracyMeters>
                  <travels:timeZone>America/Los_Angeles</travels:timeZone>
                  <travels:tags>
                    <travels:tag>canonical tag</travels:tag>
                  </travels:tags>
                  <travels:solar>
                    <travels:period>day</travels:period>
                    <travels:periodPercent>0.5</travels:periodPercent>
                  </travels:solar>
                  <travels:place>
                    <travels:name>Canonical Name</travels:name>
                    <travels:areasOfInterest>
                      <travels:areaOfInterest>Canonical AOI</travels:areaOfInterest>
                    </travels:areasOfInterest>
                  </travels:place>
                </extensions>
              </trkpt>
            </trkseg>
          </trk>
        </gpx>
        """

        let result = try GPXImporter.parse(data: Data(xml.utf8))
        let event = try XCTUnwrap(result.events.first)
        let geolocation = try XCTUnwrap(result.trackPoints.first?.geolocation)

        XCTAssertEqual(event.source, .imported)
        XCTAssertEqual(event.horizontalAccuracy, 12)
        XCTAssertEqual(event.solarPeriod, .day)
        XCTAssertEqual(try XCTUnwrap(event.solarPeriodPercent), 0.5, accuracy: 0.0001)
        XCTAssertEqual(event.tags, "canonical tag")
        XCTAssertEqual(geolocation.name, "Canonical Name")
        XCTAssertEqual(geolocation.timeZoneIdentifier, "America/Los_Angeles")
        XCTAssertEqual(geolocation.areasOfInterest, ["Canonical AOI"])
    }

    func testGPXExportUsesCanonicalTravelsNamespaceAndStandardFields() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let geolocation = Geolocation(
            latitude: 51.5007,
            longitude: -0.1246,
            radius: 25,
            timeZoneIdentifier: "Europe/London",
            name: "Westminster",
            locality: "London",
            administrativeArea: "England",
            country: "United Kingdom",
            areasOfInterest: ["Big Ben", "Westminster"]
        )
        let geolocationID = try store.saveGeolocation(geolocation)
        let event = LocationEvent(
            latitude: 51.5007,
            longitude: -0.1246,
            horizontalAccuracy: 12,
            verticalAccuracy: 8,
            altitude: 42,
            course: 90,
            speed: 1.2,
            timestamp: Date(timeIntervalSinceReferenceDate: 1_000),
            localizedDate: "2001-01-01",
            source: .manual,
            geolocationID: geolocationID,
            note: "Westminster",
            tags: "museum\nart",
            externalReference: "ref-1",
            photoFilename: "photo-1.jpg",
            isDemo: true,
            solarPeriod: .day,
            solarPeriodPercent: 0.5,
            solarPeriodCalculatedAt: Date(timeIntervalSinceReferenceDate: 1_500)
        )
        _ = try store.saveEvent(event)

        let xml = try GPXExporter.export(events: try store.allEvents(), title: "Sample & Track")
        XCTAssertTrue(xml.contains("xmlns:travels=\"https://github.com/dkrnet/travels-ios/gpx/extensions/1\""))
        XCTAssertTrue(xml.contains("<name>Sample &amp; Track</name>"))
        XCTAssertTrue(xml.contains("<ele>42.0</ele>"))
        XCTAssertTrue(xml.contains("<time>2001-01-01T00:16:40Z</time>"))
        XCTAssertTrue(xml.contains("<name>Westminster</name>"))
        XCTAssertTrue(xml.contains("<cmt>Westminster</cmt>"))
        XCTAssertTrue(xml.contains("<desc>Westminster, London, England, United Kingdom</desc>"))
        XCTAssertTrue(xml.contains("<src>Manual</src>"))
        XCTAssertTrue(xml.contains("<travels:horizontalAccuracyMeters>12.0</travels:horizontalAccuracyMeters>"))
        XCTAssertTrue(xml.contains("<travels:verticalAccuracyMeters>8.0</travels:verticalAccuracyMeters>"))
        XCTAssertTrue(xml.contains("<travels:headingDegrees>90.0</travels:headingDegrees>"))
        XCTAssertTrue(xml.contains("<travels:speedMetersPerSecond>1.2</travels:speedMetersPerSecond>"))
        XCTAssertTrue(xml.contains("<travels:timeZone>Europe/London</travels:timeZone>"))
        XCTAssertTrue(xml.contains("<travels:localizedDateKey>2001-01-01</travels:localizedDateKey>"))
        XCTAssertTrue(xml.contains("<travels:source>Manual</travels:source>"))
        XCTAssertTrue(xml.contains("<travels:tags>"))
        XCTAssertTrue(xml.contains("<travels:tag>museum</travels:tag>"))
        XCTAssertTrue(xml.contains("<travels:tag>art</travels:tag>"))
        XCTAssertTrue(xml.contains("<travels:externalReference>ref-1</travels:externalReference>"))
        XCTAssertTrue(xml.contains("<travels:photoFilename>photo-1.jpg</travels:photoFilename>"))
        XCTAssertTrue(xml.contains("<travels:demoData>true</travels:demoData>"))
        XCTAssertTrue(xml.contains("<travels:solar>"))
        XCTAssertTrue(xml.contains("<travels:period>"))
        XCTAssertTrue(xml.contains("<travels:calculatedAt>"))
        XCTAssertTrue(xml.contains("<travels:place>"))
        XCTAssertTrue(xml.contains("<travels:areasOfInterest>"))
        XCTAssertTrue(xml.contains("<travels:areaOfInterest>Big Ben</travels:areaOfInterest>"))
        XCTAssertFalse(xml.contains("<travels:id>"))
        XCTAssertFalse(xml.contains("geolocationID"))
    }

    func testGPXExportRoundTripsEscapedText() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let geolocation = Geolocation(
            latitude: 37.3317,
            longitude: -122.0301,
            timeZoneIdentifier: "America/Los_Angeles",
            name: "Tom & Jerry Park",
            locality: "Cupertino",
            administrativeArea: "California",
            country: "United States",
            areasOfInterest: ["Apple & Park", "Visitor <Center>"]
        )
        let geolocationID = try store.saveGeolocation(geolocation)
        _ = try store.saveEvent(
            LocationEvent(
                latitude: 37.3317,
                longitude: -122.0301,
                timestamp: Date(timeIntervalSinceReferenceDate: 2_000),
                localizedDate: "2001-01-01",
                source: .manual,
                geolocationID: geolocationID,
                note: "Note with <angle> & ampersands",
                tags: "Museum & art\nFood <travel>"
            )
        )

        let exported = try GPXExporter.export(events: try store.allEvents(), title: "Tom & Jerry <Trip>")
        XCTAssertTrue(exported.contains("Tom &amp; Jerry &lt;Trip&gt;"))
        XCTAssertTrue(exported.contains("Note with &lt;angle&gt; &amp; ampersands"))
        XCTAssertTrue(exported.contains("<travels:tag>Museum &amp; art</travels:tag>"))
        XCTAssertTrue(exported.contains("<travels:tag>Food &lt;travel&gt;</travels:tag>"))
        XCTAssertTrue(exported.contains("<travels:areaOfInterest>Apple &amp; Park</travels:areaOfInterest>"))
        XCTAssertTrue(exported.contains("<travels:areaOfInterest>Visitor &lt;Center&gt;</travels:areaOfInterest>"))

        let imported = try GPXImporter.parse(data: Data(exported.utf8))
        let importedEvent = try XCTUnwrap(imported.events.first)
        let importedGeolocation = try XCTUnwrap(imported.trackPoints.first?.geolocation)
        XCTAssertEqual(importedEvent.note, "Note with <angle> & ampersands")
        XCTAssertEqual(importedEvent.tags, "Museum & art\nFood <travel>")
        XCTAssertEqual(importedGeolocation.name, "Tom & Jerry Park")
        XCTAssertEqual(importedGeolocation.areasOfInterest, ["Apple & Park", "Visitor <Center>"])
    }

    func testGPXReimportReusesExactDuplicateGeolocationsAndEvents() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let originalTimestamp = Date(timeIntervalSinceReferenceDate: 2_000.125)
        let geolocation = Geolocation(
            latitude: 37.3317,
            longitude: -122.0301,
            radius: 25,
            timeZoneIdentifier: "America/Los_Angeles",
            name: "Apple Park",
            locality: "Cupertino",
            administrativeArea: "California",
            country: "United States",
            areasOfInterest: ["Apple Park"]
        )
        let geolocationID = try store.saveGeolocation(geolocation)
        _ = try store.saveEvent(
            LocationEvent(
                latitude: 37.3317,
                longitude: -122.0301,
                timestamp: originalTimestamp,
                localizedDate: "2001-01-01",
                source: .imported,
                geolocationID: geolocationID,
                note: "Round-trip"
            )
        )

        let exported = try GPXExporter.export(events: try store.allEvents(), title: "Round Trip")
        let imported = try GPXImporter.parse(data: Data(exported.utf8))
        let importedGeolocation = try XCTUnwrap(imported.trackPoints.first?.geolocation)
        let duplicateGeolocationID = try store.saveGeolocation(importedGeolocation)
        XCTAssertEqual(duplicateGeolocationID, geolocationID)

        var importedEvent = try XCTUnwrap(imported.events.first)
        XCTAssertEqual(importedEvent.timestamp, originalTimestamp)
        importedEvent.geolocationID = duplicateGeolocationID
        let duplicateEventID = try store.saveEvent(importedEvent)
        XCTAssertEqual(duplicateEventID, try XCTUnwrap(store.allEvents().first?.event.id))
        XCTAssertEqual(try store.allEvents().count, 1)
    }

    func testDemoDataSeedsThreeDaysBeforeLaunchAndCanBeHidden() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let referenceDate = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let trackURLs = [
            root.appendingPathComponent("Fixtures/demo-2017-06-30.gpx"),
            root.appendingPathComponent("Fixtures/demo-2018-01-05.gpx"),
            root.appendingPathComponent("Fixtures/demo-2018-07-06.gpx")
        ]
        try DemoData.seed(into: store, anchoredTo: referenceDate, trackURLs: trackURLs)

        let allEvents = try store.allEvents()
        XCTAssertGreaterThan(allEvents.count, 0)
        XCTAssertTrue(allEvents.allSatisfy { $0.event.source == .simulated })
        XCTAssertTrue(allEvents.allSatisfy { $0.event.note.isEmpty })
        XCTAssertTrue(allEvents.allSatisfy { $0.geolocation != nil })
        XCTAssertTrue(allEvents.contains { $0.event.speed > 0 })
        XCTAssertTrue(allEvents.contains { $0.event.course >= 0 })
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

    func testSQLiteStoreCanReplaceAnExistingEventInPlace() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let originalID = try store.saveEvent(
            LocationEvent(
                latitude: 37.0,
                longitude: -122.0,
                horizontalAccuracy: 25,
                altitude: 100,
                course: 90,
                speed: 3,
                timestamp: Date(timeIntervalSinceReferenceDate: 1_000),
                localizedDate: "2001-01-01",
                source: .locationServices
            )
        )

        try store.replaceEvent(
            eventID: originalID,
            with: LocationEvent(
                latitude: 37.0,
                longitude: -122.0,
                horizontalAccuracy: 8,
                altitude: 120,
                course: 180,
                speed: 0.5,
                timestamp: Date(timeIntervalSinceReferenceDate: 1_100),
                localizedDate: "2001-01-02",
                source: .locationServices
            )
        )

        XCTAssertEqual(try store.eventCount(), 1)
        let latest = try store.latestEvent()
        XCTAssertEqual(latest?.id, originalID)
        XCTAssertEqual(latest?.horizontalAccuracy, 8)
        XCTAssertEqual(latest?.speed, 0.5)
        XCTAssertEqual(latest?.timestamp.timeIntervalSinceReferenceDate, 1_100)
    }

    func testSQLiteStoreCanDeleteAnEvent() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let eventID = try store.saveEvent(
            LocationEvent(
                latitude: 37.0,
                longitude: -122.0,
                timestamp: Date(timeIntervalSinceReferenceDate: 1_000),
                localizedDate: "2001-01-01",
                source: .manual
            )
        )

        XCTAssertEqual(try store.eventCount(), 1)
        try store.deleteEvent(eventID: eventID)
        XCTAssertEqual(try store.eventCount(), 0)
        XCTAssertEqual(try store.allEvents().count, 0)
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

    func testAttachGeolocationRecalculatesPreviouslyUnknownSolarPeriod() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let eventDate = makeDate(
            year: 2026,
            month: 6,
            day: 7,
            hour: 20,
            minute: 10,
            timeZone: TimeZone(identifier: "America/Los_Angeles")!
        )
        let eventID = try store.saveEvent(
            LocationEvent(
                latitude: 33.8403,
                longitude: -118.0037,
                timestamp: eventDate,
                localizedDate: TravelsDateTools.localizedDayString(for: eventDate, timeZoneIdentifier: "America/Los_Angeles"),
                source: .photo
            )
        )
        let geolocationID = try store.saveGeolocation(
            Geolocation(
                latitude: 33.8403,
                longitude: -118.0037,
                timeZoneIdentifier: "America/Los_Angeles",
                name: "Buena Park"
            )
        )

        let before = try XCTUnwrap(try store.allEvents().first(where: { $0.event.id == eventID }))
        XCTAssertEqual(before.event.solarPeriod, .unknown)
        XCTAssertNotNil(before.event.solarPeriodCalculatedAt)

        try store.attachGeolocation(geolocationID, toEvent: eventID)

        let solarEvents = try XCTUnwrap(losAngelesSolarEvents(on: eventDate))
        let sunset = try XCTUnwrap(solarEvents.sunset)
        let civilDusk = try XCTUnwrap(solarEvents.civilDusk)
        let expectedPercent = eventDate.timeIntervalSince(sunset) / civilDusk.timeIntervalSince(sunset)

        let saved = try XCTUnwrap(try store.allEvents().first(where: { $0.event.id == eventID }))
        XCTAssertEqual(saved.geolocation?.timeZoneIdentifier, "America/Los_Angeles")
        XCTAssertEqual(saved.event.solarPeriod, .eveningCivilTwilight)
        XCTAssertNotNil(saved.event.solarPeriodCalculatedAt)
        XCTAssertEqual(try XCTUnwrap(saved.event.solarPeriodPercent), expectedPercent, accuracy: 0.0001)
    }

    func testLoadingUnknownSolarPeriodRecalculatesAndPersistsIt() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let eventDate = makeDate(
            year: 2026,
            month: 6,
            day: 7,
            hour: 20,
            minute: 10,
            timeZone: TimeZone(identifier: "America/Los_Angeles")!
        )
        let geolocationID = try store.saveGeolocation(
            Geolocation(
                latitude: 33.8403,
                longitude: -118.0037,
                timeZoneIdentifier: "America/Los_Angeles",
                name: "Buena Park"
            )
        )
        let eventID = try store.saveEvent(
            LocationEvent(
                latitude: 33.8403,
                longitude: -118.0037,
                timestamp: eventDate,
                localizedDate: TravelsDateTools.localizedDayString(for: eventDate, timeZoneIdentifier: "America/Los_Angeles"),
                source: .photo,
                geolocationID: geolocationID
            )
        )
        let inspector = try SQLiteDatabase(path: url.path)
        try inspector.execute("UPDATE events SET solar_period = 'unknown', solar_period_percent = NULL, solar_period_calculated_at = NULL WHERE id = ?", parameters: [.integer(eventID)])

        let details = try store.allEvents()
        let saved = try XCTUnwrap(details.first(where: { $0.event.id == eventID }))
        XCTAssertEqual(saved.event.solarPeriod, .eveningCivilTwilight)
        XCTAssertNotNil(saved.event.solarPeriodCalculatedAt)
        XCTAssertNotNil(saved.event.solarPeriodPercent)

        let persisted = try XCTUnwrap(try store.allEvents().first(where: { $0.event.id == eventID }))
        XCTAssertEqual(persisted.event.solarPeriod, .eveningCivilTwilight)
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
            horizontalAccuracy: 12,
            verticalAccuracy: 8,
            altitude: 42,
            course: 90,
            speed: 1.2,
            timestamp: Date(timeIntervalSinceReferenceDate: 1_000),
            localizedDate: "2001-01-01",
            source: .manual,
            note: "Westminster",
            tags: "museum\nart",
            externalReference: "ref-1",
            photoFilename: "photo-1.jpg",
            isDemo: true,
            solarPeriod: .day,
            solarPeriodPercent: 0.5,
            solarPeriodCalculatedAt: Date(timeIntervalSinceReferenceDate: 1_500)
        )
        let geolocation = Geolocation(
            latitude: 51.5007,
            longitude: -0.1246,
            radius: 25,
            timeZoneIdentifier: "Europe/London",
            name: "Westminster",
            locality: "London",
            administrativeArea: "England",
            country: "United Kingdom",
            areasOfInterest: ["Big Ben", "Westminster"]
        )
        let geolocationID = try store.saveGeolocation(geolocation)
        _ = try store.saveEvent(LocationEvent(id: nil, latitude: event.latitude, longitude: event.longitude, horizontalAccuracy: event.horizontalAccuracy, verticalAccuracy: event.verticalAccuracy, altitude: event.altitude, course: event.course, speed: event.speed, timestamp: event.timestamp, localizedDate: event.localizedDate, source: event.source, geolocationID: geolocationID, note: event.note, tags: event.tags, externalReference: event.externalReference, photoFilename: event.photoFilename, isDemo: event.isDemo, solarPeriod: event.solarPeriod, solarPeriodPercent: event.solarPeriodPercent, solarPeriodCalculatedAt: event.solarPeriodCalculatedAt))

        let details = try store.allEvents()
        let xml = try GPXExporter.export(events: details, title: "Sample & Track")
        XCTAssertTrue(xml.contains("xmlns:travels=\"https://github.com/dkrnet/travels-ios/gpx/extensions/1\""))
        XCTAssertTrue(xml.contains("<name>Sample &amp; Track</name>"))
        XCTAssertTrue(xml.contains("<ele>42.0</ele>"))
        XCTAssertTrue(xml.contains("<time>2001-01-01T00:16:40Z</time>"))
        XCTAssertTrue(xml.contains("<desc>Westminster, London, England, United Kingdom</desc>"))
        XCTAssertTrue(xml.contains("<cmt>Westminster</cmt>"))
        XCTAssertTrue(xml.contains("<src>Manual</src>"))
        XCTAssertTrue(xml.contains("<travels:horizontalAccuracyMeters>12.0</travels:horizontalAccuracyMeters>"))
        XCTAssertTrue(xml.contains("<travels:timeZone>Europe/London</travels:timeZone>"))
        XCTAssertTrue(xml.contains("<travels:localizedDateKey>2001-01-01</travels:localizedDateKey>"))
        XCTAssertTrue(xml.contains("<travels:source>Manual</travels:source>"))
        XCTAssertTrue(xml.contains("<travels:tags>"))
        XCTAssertTrue(xml.contains("<travels:tag>museum</travels:tag>"))
        XCTAssertTrue(xml.contains("<travels:tag>art</travels:tag>"))
        XCTAssertTrue(xml.contains("<travels:externalReference>ref-1</travels:externalReference>"))
        XCTAssertTrue(xml.contains("<travels:photoFilename>photo-1.jpg</travels:photoFilename>"))
        XCTAssertTrue(xml.contains("<travels:demoData>true</travels:demoData>"))
        XCTAssertTrue(xml.contains("<travels:solar>"))
        XCTAssertTrue(xml.contains("<travels:period>"))
        XCTAssertTrue(xml.contains("<travels:calculatedAt>"))
        XCTAssertTrue(xml.contains("<travels:place>"))
        XCTAssertTrue(xml.contains("<travels:areasOfInterest>"))
        XCTAssertTrue(xml.contains("<travels:areaOfInterest>Big Ben</travels:areaOfInterest>"))
        XCTAssertFalse(xml.contains("<travels:id>"))
        XCTAssertFalse(xml.contains("geolocationID"))
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

    func testDemoFlagRoundTripsThroughStore() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try TravelsStore(url: url)
        let event = LocationEvent(
            latitude: 34.0522,
            longitude: -118.2437,
            timestamp: Date(timeIntervalSinceReferenceDate: 4_000),
            localizedDate: "2001-01-01",
            source: .simulated,
            note: "Demo"
        )
        _ = try store.saveEvent(event, isDemo: true)

        let saved = try store.allEvents().first
        XCTAssertEqual(saved?.event.isDemo, true)
        XCTAssertEqual(try store.allEvents(includeDemo: false).count, 0)
    }
}
