// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.

import Foundation
import XCTest
@testable import TravelsCore

final class AppSettingsTests: XCTestCase {
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

    func testAlwaysOnHighPrecisionLocationDefaultsToOff() {
        XCTAssertFalse(AppSettings().alwaysOnHighPrecisionLocation)
    }

    func testAlwaysOnHighPrecisionLocationPersistsThroughSettingsStore() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = rootURL.appendingPathComponent("Travels.sqlite")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let store = try TravelsStore(url: databaseURL)
        let settingsStore = SettingsStore(store: store)
        var settings = AppSettings()
        settings.alwaysOnHighPrecisionLocation = true

        try settingsStore.save(settings)

        let reloaded = try settingsStore.load()
        XCTAssertTrue(reloaded.alwaysOnHighPrecisionLocation)
    }
}
