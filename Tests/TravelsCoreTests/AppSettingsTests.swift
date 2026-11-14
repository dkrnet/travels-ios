// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.

import Foundation
import XCTest
@testable import TravelsCore

final class AppSettingsTests: XCTestCase {
    func testDemoDataDatesAreTheThreeDaysBeforeFirstLaunch() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let referenceDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 12)))

        let dates = DemoData.displayedDates(anchoredTo: referenceDate, calendar: calendar)
        let components = dates.map { calendar.dateComponents([.year, .month, .day], from: $0) }

        XCTAssertEqual(components.map(\.year), [2026, 2026, 2026])
        XCTAssertEqual(components.map(\.month), [11, 11, 11])
        XCTAssertEqual(components.map(\.day), [11, 12, 13])
    }

    func testFreshSettingsStoreDisablesAddressResolution() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = rootURL.appendingPathComponent("Travels.sqlite")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let store = try TravelsStore(url: databaseURL)
        let settingsStore = SettingsStore(store: store)

        let loaded = try settingsStore.load()
        XCTAssertFalse(loaded.resolveAddresses)
        XCTAssertFalse(loaded.resolveMissingAddresses)
    }

    func testDefaultSettingsDisableAddressResolution() {
        let settings = AppSettings()
        XCTAssertFalse(settings.resolveAddresses)
        XCTAssertFalse(settings.resolveMissingAddresses)
    }

    func testPreciseLocationModeDefaultsToAutomatic() {
        XCTAssertEqual(AppSettings().preciseLocationMode, .automatic)
    }

    func testLocationDetailModeDefaultsToBalanced() {
        XCTAssertEqual(AppSettings().locationDetailMode, .balanced)
    }

    func testPreciseLocationModePersistsThroughSettingsStore() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = rootURL.appendingPathComponent("Travels.sqlite")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let store = try TravelsStore(url: databaseURL)
        let settingsStore = SettingsStore(store: store)
        var settings = AppSettings()
        settings.preciseLocationMode = .alwaysOff
        settings.locationDetailMode = .roadTrip

        try settingsStore.save(settings)

        let reloaded = try settingsStore.load()
        XCTAssertEqual(reloaded.preciseLocationMode, .alwaysOff)
        XCTAssertEqual(reloaded.locationDetailMode, .roadTrip)
    }

    func testMissingPreciseLocationModeDecodesAsAutomatic() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))

        XCTAssertEqual(settings.preciseLocationMode, .automatic)
    }

    func testLegacyAlwaysOnHighPrecisionFalseMigratesToAutomatic() throws {
        let json = #"{"alwaysOnHighPrecisionLocation":false}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.preciseLocationMode, .automatic)
    }

    func testLegacyAlwaysOnHighPrecisionTrueMigratesToAlwaysOn() throws {
        let json = #"{"alwaysOnHighPrecisionLocation":true}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.preciseLocationMode, .alwaysOn)
    }

    func testPreciseLocationModeRawValuesDecode() throws {
        let automatic = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"preciseLocationMode":"automatic"}"#.utf8))
        let alwaysOn = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"preciseLocationMode":"alwaysOn"}"#.utf8))
        let alwaysOff = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"preciseLocationMode":"alwaysOff"}"#.utf8))

        XCTAssertEqual(automatic.preciseLocationMode, .automatic)
        XCTAssertEqual(alwaysOn.preciseLocationMode, .alwaysOn)
        XCTAssertEqual(alwaysOff.preciseLocationMode, .alwaysOff)
    }

    func testUnknownPreciseLocationModeFallsBackToAutomatic() throws {
        let json = #"{"preciseLocationMode":"nearbyThunderstorm"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.preciseLocationMode, .automatic)
    }

    func testFreshStorePresentsFirstLaunchWelcome() {
        let disposition = FirstLaunchWelcomePolicy.disposition(
            storedValue: nil,
            storeExistedBeforeLaunch: false
        )

        XCTAssertEqual(disposition, .pending)
        XCTAssertTrue(disposition.shouldPresent)
    }

    func testExistingStoreDoesNotReceiveNewInstallWelcomeAfterUpgrade() {
        let disposition = FirstLaunchWelcomePolicy.disposition(
            storedValue: nil,
            storeExistedBeforeLaunch: true
        )

        XCTAssertEqual(disposition, .suppressedForExistingStore)
        XCTAssertFalse(disposition.shouldPresent)
    }

    func testPendingWelcomeRemainsPendingAfterInterruptedLaunch() {
        let disposition = FirstLaunchWelcomePolicy.disposition(
            storedValue: FirstLaunchWelcomeDisposition.pending.rawValue,
            storeExistedBeforeLaunch: true
        )

        XCTAssertTrue(disposition.shouldPresent)
    }

    func testCompletedWelcomeDoesNotPresentAgain() {
        let disposition = FirstLaunchWelcomePolicy.disposition(
            storedValue: FirstLaunchWelcomeDisposition.completed.rawValue,
            storeExistedBeforeLaunch: true
        )

        XCTAssertFalse(disposition.shouldPresent)
    }
}
