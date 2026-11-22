// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.

import Foundation
import XCTest
@testable import TravelsCore

final class DatabaseExportTests: XCTestCase {
    func testDatabaseExportCreatesHealthyIndependentSnapshot() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceURL = rootURL.appendingPathComponent("Travels.sqlite")
        let exportURL = rootURL.appendingPathComponent("Travels-export.sqlite")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let source = try TravelsStore(url: sourceURL)
        let timestamp = Date(timeIntervalSinceReferenceDate: 12_345)
        _ = try source.saveEvent(
            LocationEvent(
                latitude: 33.8,
                longitude: -118.0,
                timestamp: timestamp,
                source: .locationServices,
                note: "Snapshot event"
            )
        )

        try source.exportDatabase(to: exportURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: exportURL.path + "-wal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: exportURL.path + "-shm"))

        let snapshot = try TravelsStore(url: exportURL)
        XCTAssertTrue(try snapshot.databaseHealthReport().isHealthy)
        XCTAssertEqual(try snapshot.eventCount(), 1)
        XCTAssertEqual(try snapshot.latestEvent()?.note, "Snapshot event")

        _ = try source.saveEvent(
            LocationEvent(
                latitude: 34.0,
                longitude: -118.2,
                timestamp: timestamp.addingTimeInterval(60),
                source: .locationServices
            )
        )

        XCTAssertEqual(try source.eventCount(), 2)
        XCTAssertEqual(try snapshot.eventCount(), 1)
    }

    func testDatabaseExportCannotReplaceActiveDatabase() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceURL = rootURL.appendingPathComponent("Travels.sqlite")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let source = try TravelsStore(url: sourceURL)
        _ = try source.saveEvent(
            LocationEvent(
                latitude: 33.8,
                longitude: -118.0,
                timestamp: Date(timeIntervalSinceReferenceDate: 12_345),
                source: .locationServices
            )
        )

        XCTAssertThrowsError(try source.exportDatabase(to: sourceURL))
        XCTAssertEqual(try source.eventCount(), 1)
        XCTAssertTrue(try source.databaseHealthReport().isHealthy)
    }
}
