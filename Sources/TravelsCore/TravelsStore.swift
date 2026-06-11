// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.

import Foundation

public final class TravelsStore: @unchecked Sendable {
    private var database: SQLiteDatabase
    public let databaseURL: URL

    public struct DatabaseHealthReport: Equatable, Sendable {
        public let isHealthy: Bool
        public let issues: [String]

        public init(isHealthy: Bool, issues: [String]) {
            self.isHealthy = isHealthy
            self.issues = issues
        }

        public var summary: String {
            issues.joined(separator: "; ")
        }
    }

    public struct DatabaseRepairOutcome: Equatable, Sendable {
        public let backupDirectory: URL?
        public let issues: [String]

        public init(backupDirectory: URL?, issues: [String]) {
            self.backupDirectory = backupDirectory
            self.issues = issues
        }

        public var userFacingMessage: String {
            var message = "Travels found a database problem and rebuilt a fresh database."
            if let backupDirectory {
                message += " A backup was saved in \(backupDirectory.lastPathComponent)."
            }
            return message
        }
    }

    public init(path: String) throws {
        databaseURL = URL(fileURLWithPath: path)
        database = try SQLiteDatabase(path: path)
        try migrate()
    }

    public convenience init(url: URL) throws {
        try self.init(path: url.path)
    }

    public func databaseHealthReport() throws -> DatabaseHealthReport {
        let integrityMessages = try database.integrityCheck().map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let nonEmptyIntegrityMessages = integrityMessages.filter { !$0.isEmpty }
        let integrityHealthy = !nonEmptyIntegrityMessages.isEmpty && nonEmptyIntegrityMessages.allSatisfy {
            $0.caseInsensitiveCompare("ok") == .orderedSame
        }

        let foreignKeyRows = try database.query("PRAGMA foreign_key_check")
        let foreignKeyIssues = foreignKeyRows.map { row -> String in
            let table = row["table"]?.string ?? "unknown table"
            let rowID = row["rowid"]?.int64.map(String.init) ?? "?"
            let parent = row["parent"]?.string ?? "unknown parent"
            return "foreign_key_check failed for \(table) row \(rowID) referencing \(parent)"
        }

        var issues = nonEmptyIntegrityMessages
        issues.append(contentsOf: foreignKeyIssues)
        if issues.isEmpty {
            issues = ["ok"]
        }

        return DatabaseHealthReport(
            isHealthy: integrityHealthy && foreignKeyIssues.isEmpty,
            issues: issues
        )
    }

    @discardableResult
    public func validateAndRepairIfNeeded(quarantineRoot: URL? = nil) throws -> DatabaseRepairOutcome? {
        do {
            let report = try databaseHealthReport()
            guard !report.isHealthy else { return nil }
            return try repairDatabase(using: report.issues, quarantineRoot: quarantineRoot)
        } catch {
            return try repairDatabase(using: [error.localizedDescription], quarantineRoot: quarantineRoot)
        }
    }

    public func migrate() throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS geolocations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            latitude REAL NOT NULL DEFAULT 0,
            longitude REAL NOT NULL DEFAULT 0,
            radius REAL NOT NULL DEFAULT 0,
            identifier TEXT NOT NULL DEFAULT '',
            horizontalAccuracy REAL NOT NULL DEFAULT -1,
            verticalAccuracy REAL NOT NULL DEFAULT -1,
            altitude REAL NOT NULL DEFAULT 0,
            timestamp REAL,
            minLatitude REAL,
            maxLatitude REAL,
            minLongitude REAL,
            maxLongitude REAL,
            timeZoneIdentifier TEXT NOT NULL DEFAULT '',
            name TEXT NOT NULL DEFAULT '',
            subThoroughfare TEXT NOT NULL DEFAULT '',
            thoroughfare TEXT NOT NULL DEFAULT '',
            subLocality TEXT NOT NULL DEFAULT '',
            locality TEXT NOT NULL DEFAULT '',
            subAdministrativeArea TEXT NOT NULL DEFAULT '',
            administrativeArea TEXT NOT NULL DEFAULT '',
            postalCode TEXT NOT NULL DEFAULT '',
            isoCountryCode TEXT NOT NULL DEFAULT '',
            country TEXT NOT NULL DEFAULT '',
            inlandWater TEXT NOT NULL DEFAULT '',
            ocean TEXT NOT NULL DEFAULT '',
            areasOfInterest TEXT NOT NULL DEFAULT ''
        )
        """)

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
            solar_period TEXT NOT NULL DEFAULT 'unknown',
            solar_period_percent REAL,
            solar_period_calculated_at DATETIME,
            twilight_phase TEXT NOT NULL DEFAULT 'none',
            twilight_percent REAL,
            twilight_calculated_at DATETIME,
            UNIQUE(latitude, longitude, timestamp, source, externalReference),
            FOREIGN KEY(geolocationID) REFERENCES geolocations(id)
        )
        """)

        try database.execute("""
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL
        )
        """)

        try ensureColumnExists(table: "events", column: "photoFilename", definition: "TEXT NOT NULL DEFAULT ''")
        try ensureColumnExists(table: "events", column: "solar_period", definition: "TEXT NOT NULL DEFAULT 'unknown'")
        try ensureColumnExists(table: "events", column: "solar_period_percent", definition: "REAL")
        try ensureColumnExists(table: "events", column: "solar_period_calculated_at", definition: "DATETIME")
        try ensureColumnExists(table: "events", column: "twilight_phase", definition: "TEXT NOT NULL DEFAULT 'none'")
        try ensureColumnExists(table: "events", column: "twilight_percent", definition: "REAL")
        try ensureColumnExists(table: "events", column: "twilight_calculated_at", definition: "DATETIME")
        try database.execute("CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(timestamp)")
        try database.execute("CREATE INDEX IF NOT EXISTS idx_events_localized_date ON events(localizedDate)")
        try database.execute("CREATE INDEX IF NOT EXISTS idx_events_source ON events(source)")
        try database.execute("CREATE INDEX IF NOT EXISTS idx_events_twilight_calculated_at_timestamp ON events(twilight_calculated_at, timestamp DESC)")
        try database.execute("CREATE INDEX IF NOT EXISTS idx_events_solar_period_calculated_at_timestamp ON events(solar_period_calculated_at, timestamp DESC)")
        try database.execute("CREATE INDEX IF NOT EXISTS idx_geolocations_place ON geolocations(country, administrativeArea, subAdministrativeArea, locality)")
    }

    @discardableResult
    public func saveGeolocation(_ geolocation: Geolocation) throws -> Int64 {
        if let duplicate = try findDuplicate(geolocation) {
            return duplicate.id ?? 0
        }
        let areas = Geolocation.normalizedAreasOfInterest(geolocation.areasOfInterest).joined(separator: "|||TRAVELS|||")
        try database.execute(
            """
            INSERT INTO geolocations (
                latitude, longitude, radius, identifier, horizontalAccuracy, verticalAccuracy, altitude,
                timestamp, minLatitude, maxLatitude, minLongitude, maxLongitude, timeZoneIdentifier,
                name, subThoroughfare, thoroughfare, subLocality, locality, subAdministrativeArea,
                administrativeArea, postalCode, isoCountryCode, country, inlandWater, ocean, areasOfInterest
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            parameters: [
                .real(geolocation.latitude),
                .real(geolocation.longitude),
                .real(geolocation.radius),
                .text(geolocation.identifier),
                .real(geolocation.horizontalAccuracy),
                .real(geolocation.verticalAccuracy),
                .real(geolocation.altitude),
                optionalDate(geolocation.timestamp),
                optionalDouble(geolocation.minLatitude),
                optionalDouble(geolocation.maxLatitude),
                optionalDouble(geolocation.minLongitude),
                optionalDouble(geolocation.maxLongitude),
                .text(geolocation.timeZoneIdentifier),
                .text(geolocation.name),
                .text(geolocation.subThoroughfare),
                .text(geolocation.thoroughfare),
                .text(geolocation.subLocality),
                .text(geolocation.locality),
                .text(geolocation.subAdministrativeArea),
                .text(geolocation.administrativeArea),
                .text(geolocation.postalCode),
                .text(geolocation.isoCountryCode),
                .text(geolocation.country),
                .text(geolocation.inlandWater),
                .text(geolocation.ocean),
                .text(areas)
            ]
        )
        return database.lastInsertRowID()
    }

    public func findDuplicate(_ geolocation: Geolocation) throws -> Geolocation? {
        let areas = Geolocation.normalizedAreasOfInterest(geolocation.areasOfInterest).joined(separator: "|||TRAVELS|||")
        let rows = try database.query(
            """
            SELECT * FROM geolocations
            WHERE latitude = ? AND longitude = ? AND radius = ?
            AND horizontalAccuracy = ? AND verticalAccuracy = ? AND altitude = ?
            AND minLatitude IS ? AND maxLatitude IS ?
            AND minLongitude IS ? AND maxLongitude IS ?
            AND timeZoneIdentifier = ?
            AND name = ? AND subThoroughfare = ? AND thoroughfare = ?
            AND subLocality = ? AND locality = ?
            AND subAdministrativeArea = ? AND administrativeArea = ?
            AND postalCode = ? AND isoCountryCode = ?
            AND country = ? AND inlandWater = ? AND ocean = ?
            AND areasOfInterest = ?
            LIMIT 1
            """,
            parameters: [
                .real(geolocation.latitude),
                .real(geolocation.longitude),
                .real(geolocation.radius),
                .real(geolocation.horizontalAccuracy),
                .real(geolocation.verticalAccuracy),
                .real(geolocation.altitude),
                optionalDouble(geolocation.minLatitude),
                optionalDouble(geolocation.maxLatitude),
                optionalDouble(geolocation.minLongitude),
                optionalDouble(geolocation.maxLongitude),
                .text(geolocation.timeZoneIdentifier),
                .text(geolocation.name),
                .text(geolocation.subThoroughfare),
                .text(geolocation.thoroughfare),
                .text(geolocation.subLocality),
                .text(geolocation.locality),
                .text(geolocation.subAdministrativeArea),
                .text(geolocation.administrativeArea),
                .text(geolocation.postalCode),
                .text(geolocation.isoCountryCode),
                .text(geolocation.country),
                .text(geolocation.inlandWater),
                .text(geolocation.ocean),
                .text(areas)
            ]
        )
        return rows.first.map(geolocation(from:))
    }

    @discardableResult
    public func saveEvent(_ event: LocationEvent, isDemo: Bool = false) throws -> Int64 {
        if let duplicate = try findDuplicate(event) {
            return duplicate.id ?? 0
        }
        let demoFlag = isDemo || event.isDemo
        let solar = solarStorageValues(for: event)
        try database.execute(
            """
            INSERT INTO events (
                latitude, longitude, horizontalAccuracy, verticalAccuracy, altitude, course, speed,
                timestamp, localizedDate, source, geolocationID, note, tags, externalReference, photoFilename, isDemo,
                solar_period, solar_period_percent, solar_period_calculated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            parameters: [
                .real(event.latitude),
                .real(event.longitude),
                .real(event.horizontalAccuracy),
                .real(event.verticalAccuracy),
                .real(event.altitude),
                .real(event.course),
                .real(event.speed),
                .real(event.timestamp.timeIntervalSinceReferenceDate),
                optionalString(event.localizedDate),
                .integer(Int64(event.source.rawValue)),
                optionalInt(event.geolocationID),
                .text(event.note),
                .text(event.tags),
                .text(event.externalReference),
                .text(event.photoFilename),
                .integer(demoFlag ? 1 : 0),
                .text(solar.period.rawValue),
                optionalDouble(solar.percent),
                optionalDate(solar.calculatedAt)
            ]
        )
        return database.lastInsertRowID()
    }

    public func replaceEvent(eventID: Int64, with event: LocationEvent) throws {
        let solar = solarStorageValues(for: event)
        try database.execute(
            """
            UPDATE events SET
                latitude = ?, longitude = ?, horizontalAccuracy = ?, verticalAccuracy = ?,
                altitude = ?, course = ?, speed = ?, timestamp = ?, localizedDate = ?,
                source = ?, geolocationID = ?, note = ?, tags = ?, externalReference = ?,
                photoFilename = ?, isDemo = ?, solar_period = ?, solar_period_percent = ?, solar_period_calculated_at = ?
            WHERE id = ?
            """,
            parameters: [
                .real(event.latitude),
                .real(event.longitude),
                .real(event.horizontalAccuracy),
                .real(event.verticalAccuracy),
                .real(event.altitude),
                .real(event.course),
                .real(event.speed),
                .real(event.timestamp.timeIntervalSinceReferenceDate),
                optionalString(event.localizedDate),
                .integer(Int64(event.source.rawValue)),
                optionalInt(event.geolocationID),
                .text(event.note),
                .text(event.tags),
                .text(event.externalReference),
                .text(event.photoFilename),
                .integer(event.isDemo ? 1 : 0),
                .text(solar.period.rawValue),
                optionalDouble(solar.percent),
                optionalDate(solar.calculatedAt),
                .integer(eventID)
            ]
        )
    }

    public func events(on date: Date, includePreviousDayContext: Bool = false, includeDemo: Bool = true) throws -> [EventDetail] {
        let day = TravelsDateTools.localizedDayString(for: date, timeZoneIdentifier: nil)
        var parameters: [SQLiteValue] = [.text(day)]
        var predicate = "e.localizedDate = ?"
        if includePreviousDayContext, try dayHasVisibleNonDemoEvents(day: day, includeDemo: includeDemo) {
            let previous = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
            predicate = "(e.localizedDate = ? OR e.id = (SELECT id FROM events WHERE localizedDate = ? ORDER BY timestamp DESC LIMIT 1))"
            parameters.append(.text(TravelsDateTools.localizedDayString(for: previous, timeZoneIdentifier: nil)))
        }
        if !includeDemo {
            predicate += " AND e.isDemo = 0"
        }
        return try fetchEventDetails(where: predicate, parameters: parameters, order: "e.timestamp ASC")
    }

    public func allEvents(includeDemo: Bool = true) throws -> [EventDetail] {
        var predicate = "1 = 1"
        let parameters: [SQLiteValue] = []
        if !includeDemo {
            predicate = "e.isDemo = 0"
        }
        return try fetchEventDetails(where: predicate, parameters: parameters, order: "e.timestamp ASC")
    }

    public func checkpoint() throws {
        _ = try database.query("PRAGMA wal_checkpoint(FULL)")
    }

    public func transaction<T>(_ work: () throws -> T) throws -> T {
        try database.transaction(work)
    }

    public func close() {
        database.close()
    }

    public func search(_ criteria: SearchCriteria, includeDemo: Bool = true) throws -> [EventDetail] {
        var predicates: [String] = []
        var parameters: [SQLiteValue] = []

        if let start = criteria.startDate {
            predicates.append("e.timestamp >= ?")
            parameters.append(.real(start.timeIntervalSinceReferenceDate))
        }
        if let end = criteria.endDate {
            predicates.append("e.timestamp < ?")
            parameters.append(.real(end.timeIntervalSinceReferenceDate))
        }
        if criteria.hasNote {
            predicates.append("length(trim(e.note)) > 0")
        }
        if let value = nonAny(criteria.country) {
            predicates.append("g.country = ?")
            parameters.append(.text(value))
        }
        if let value = nonAny(criteria.administrativeArea) {
            predicates.append("g.administrativeArea = ?")
            parameters.append(.text(value))
        }
        if let value = nonAny(criteria.subAdministrativeArea) {
            predicates.append("g.subAdministrativeArea = ?")
            parameters.append(.text(value))
        }
        if let value = nonAny(criteria.locality) {
            predicates.append("g.locality = ?")
            parameters.append(.text(value))
        }
        if let value = nonAny(criteria.bodyOfWater) {
            predicates.append("(g.inlandWater = ? OR g.ocean = ?)")
            parameters.append(.text(value))
            parameters.append(.text(value))
        }
        if let source = criteria.source {
            predicates.append("e.source = ?")
            parameters.append(.integer(Int64(source.rawValue)))
        }
        let term = criteria.term.trimmingCharacters(in: .whitespacesAndNewlines)
        if !term.isEmpty {
            predicates.append("""
            (
                e.note LIKE ? OR e.tags LIKE ? OR g.name LIKE ? OR g.thoroughfare LIKE ? OR
                g.locality LIKE ? OR g.administrativeArea LIKE ? OR g.country LIKE ? OR
                g.areasOfInterest LIKE ? OR g.inlandWater LIKE ? OR g.ocean LIKE ?
            )
            """)
            for _ in 0..<10 {
                parameters.append(.text("%\(term)%"))
            }
        }
        if !includeDemo {
            predicates.append("e.isDemo = 0")
        }

        let predicate = predicates.isEmpty ? "1 = 1" : predicates.joined(separator: " AND ")
        return try fetchEventDetails(where: predicate, parameters: parameters, order: "e.timestamp ASC")
    }

    public func updateNote(eventID: Int64, note: String) throws {
        try database.execute("UPDATE events SET note = ? WHERE id = ?", parameters: [.text(note), .integer(eventID)])
    }

    public func deleteEvent(eventID: Int64) throws {
        try database.execute("DELETE FROM events WHERE id = ?", parameters: [.integer(eventID)])
    }

    public func deleteDemoEvents() throws {
        try database.execute("DELETE FROM events WHERE isDemo = 1")
    }

    public func eventCount(includeDemo: Bool = true) throws -> Int {
        let rows = try database.query("SELECT count(*) AS count FROM events WHERE (? = 1 OR isDemo = 0)", parameters: [.integer(includeDemo ? 1 : 0)])
        return Int(rows.first?["count"]?.int64 ?? 0)
    }

    public func latestEventDate(includeDemo: Bool = true) throws -> Date? {
        let rows = try database.query(
            "SELECT timestamp FROM events WHERE (? = 1 OR isDemo = 0) ORDER BY timestamp DESC LIMIT 1",
            parameters: [.integer(includeDemo ? 1 : 0)]
        )
        return rows.first?["timestamp"]?.double.map { Date(timeIntervalSinceReferenceDate: $0) }
    }

    public func latestEvent(includeDemo: Bool = true) throws -> LocationEvent? {
        let rows = try database.query(
            """
            SELECT *
            FROM events
            WHERE (? = 1 OR isDemo = 0)
            ORDER BY timestamp DESC
            LIMIT 1
            """,
            parameters: [.integer(includeDemo ? 1 : 0)]
        )
        guard let row = rows.first else { return nil }
        let event = event(from: row)
        return try refreshSolarPeriodIfNeeded(for: event)
    }

    public func fetchLocationEventsMissingSolarPeriod(limit: Int) throws -> [LocationEvent] {
        let rows = try database.query(
            """
            SELECT *
            FROM events
            WHERE solar_period_calculated_at IS NULL
            ORDER BY timestamp DESC
            LIMIT ?
            """,
            parameters: [.integer(Int64(max(limit, 0)))]
        )
        return rows.map(event(from:))
    }

    public func fetchLocationEventsMissingTwilight(limit: Int) throws -> [LocationEvent] {
        try fetchLocationEventsMissingSolarPeriod(limit: limit)
    }

    public func rebuildSolarPeriodCalculations(timeZoneIdentifier: String) throws -> Int {
        let trimmedIdentifier = timeZoneIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let timeZone = TimeZone(identifier: trimmedIdentifier) else {
            throw TravelsError.invalidTimeZoneIdentifier(trimmedIdentifier)
        }

        let rows = try database.query("SELECT * FROM events ORDER BY timestamp ASC")
        let processedAt = Date()
        try database.transaction {
            for row in rows {
                let event = event(from: row)
                guard let eventID = event.id else { continue }
                let solar = solarStorageValues(
                    for: event,
                    timeZoneOverride: timeZone,
                    calculatedAt: processedAt
                )
                try database.execute(
                    """
                    UPDATE events SET solar_period = ?, solar_period_percent = ?, solar_period_calculated_at = ?
                    WHERE id = ?
                    """,
                    parameters: [
                        .text(solar.period.rawValue),
                        optionalDouble(solar.percent),
                        optionalDate(solar.calculatedAt),
                        .integer(eventID)
                    ]
                )
            }
        }
        return rows.count
    }

    public func rebuildTwilightCalculations(timeZoneIdentifier: String) throws -> Int {
        try rebuildSolarPeriodCalculations(timeZoneIdentifier: timeZoneIdentifier)
    }

    public func oldestEventDate(includeDemo: Bool = true) throws -> Date? {
        let rows = try database.query(
            "SELECT timestamp FROM events WHERE (? = 1 OR isDemo = 0) ORDER BY timestamp ASC LIMIT 1",
            parameters: [.integer(includeDemo ? 1 : 0)]
        )
        return rows.first?["timestamp"]?.double.map { Date(timeIntervalSinceReferenceDate: $0) }
    }

    public func eventDateRange(includeDemo: Bool = true) throws -> (oldest: Date?, latest: Date?) {
        let rows = try database.query(
            """
            SELECT MIN(timestamp) AS oldest, MAX(timestamp) AS latest
            FROM events
            WHERE (? = 1 OR isDemo = 0)
            """,
            parameters: [.integer(includeDemo ? 1 : 0)]
        )
        let oldest = rows.first?["oldest"]?.double.map { Date(timeIntervalSinceReferenceDate: $0) }
        let latest = rows.first?["latest"]?.double.map { Date(timeIntervalSinceReferenceDate: $0) }
        return (oldest, latest)
    }

    public func eventsNeedingGeolocation(includeDemo: Bool = true) throws -> [EventDetail] {
        var predicate = "(e.geolocationID IS NULL OR g.id IS NULL OR trim(g.name) = '')"
        if !includeDemo {
            predicate += " AND e.isDemo = 0"
        }
        return try fetchEventDetails(where: predicate, parameters: [], order: "e.timestamp DESC")
    }

    public func attachGeolocation(_ geolocationID: Int64, toEvent eventID: Int64) throws {
        guard var event = try event(id: eventID) else { return }
        event.geolocationID = geolocationID
        try replaceEvent(eventID: eventID, with: event)
    }

    public func geolocation(id: Int64) throws -> Geolocation? {
        let rows = try database.query("SELECT * FROM geolocations WHERE id = ?", parameters: [.integer(id)])
        return rows.first.map(geolocation(from:))
    }

    public func geolocation(near latitude: Double, longitude: Double, tolerance: Double = 0.0001) throws -> Geolocation? {
        let rows = try database.query(
            """
            SELECT * FROM geolocations
            WHERE ABS(latitude - ?) <= ? AND ABS(longitude - ?) <= ?
            ORDER BY timestamp DESC, id DESC
            LIMIT 1
            """,
            parameters: [
                .real(latitude),
                .real(tolerance),
                .real(longitude),
                .real(tolerance)
            ]
        )
        return rows.first.map(geolocation(from:))
    }

    public func findDuplicate(_ event: LocationEvent) throws -> LocationEvent? {
        let rows = try database.query(
            """
            SELECT * FROM events
            WHERE latitude = ? AND longitude = ? AND timestamp = ?
            AND source = ? AND externalReference = ?
            LIMIT 1
            """,
            parameters: [
                .real(event.latitude),
                .real(event.longitude),
                .real(event.timestamp.timeIntervalSinceReferenceDate),
                .integer(Int64(event.source.rawValue)),
                .text(event.externalReference)
            ]
        )
        return rows.first.map(event(from:))
    }

    public func setSetting(_ key: String, value: String) throws {
        try database.execute(
            "INSERT INTO settings(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            parameters: [.text(key), .text(value)]
        )
    }

    public func setting(_ key: String) throws -> String? {
        try database.query("SELECT value FROM settings WHERE key = ?", parameters: [.text(key)]).first?["value"]?.string
    }

    private func fetchEventDetails(where predicate: String, parameters: [SQLiteValue], order: String) throws -> [EventDetail] {
        let rows = try database.query(
            """
            SELECT
                e.id AS event_id, e.latitude AS event_latitude, e.longitude AS event_longitude,
                e.horizontalAccuracy AS event_horizontalAccuracy, e.verticalAccuracy AS event_verticalAccuracy,
                e.altitude AS event_altitude, e.course AS event_course, e.speed AS event_speed,
                e.timestamp AS event_timestamp, e.localizedDate AS event_localizedDate,
                e.source AS event_source, e.geolocationID AS event_geolocationID, e.note AS event_note,
                e.tags AS event_tags, e.externalReference AS event_externalReference, e.photoFilename AS event_photoFilename,
                e.isDemo AS event_isDemo, e.solar_period AS event_solar_period,
                e.solar_period_percent AS event_solar_period_percent, e.solar_period_calculated_at AS event_solar_period_calculated_at,
                g.*
            FROM events e
            LEFT JOIN geolocations g ON g.id = e.geolocationID
            WHERE \(predicate)
            ORDER BY \(order)
            """,
            parameters: parameters
        )
        return try rows.map { row in
            let event = event(fromJoined: row)
            let geolocation = row["id"]?.int64 == nil ? nil : geolocation(from: row)
            let refreshedEvent = try refreshSolarPeriodIfNeeded(for: event, geolocation: geolocation)
            return EventDetail(event: refreshedEvent, geolocation: geolocation)
        }
    }

    private func repairDatabase(using issues: [String], quarantineRoot: URL?) throws -> DatabaseRepairOutcome {
        database.close()
        let backupDirectory = try Self.quarantineDatabaseFiles(at: databaseURL, quarantineRoot: quarantineRoot)
        database = try SQLiteDatabase(path: databaseURL.path)
        try migrate()
        return DatabaseRepairOutcome(backupDirectory: backupDirectory, issues: issues)
    }

    public static func quarantineDatabaseFiles(at databaseURL: URL, quarantineRoot: URL? = nil) throws -> URL {
        let fileManager = FileManager.default
        let root = quarantineRoot ?? databaseURL.deletingLastPathComponent()
        let repairsRoot = root.appendingPathComponent("Database Repairs", isDirectory: true)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let folderName = "\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8))"
        let quarantineDirectory = repairsRoot.appendingPathComponent(folderName, isDirectory: true)
        try fileManager.createDirectory(at: quarantineDirectory, withIntermediateDirectories: true)
        for url in relatedDatabaseFiles(for: databaseURL) {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let destination = quarantineDirectory.appendingPathComponent(url.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: url, to: destination)
        }
        return quarantineDirectory
    }

    private static func relatedDatabaseFiles(for databaseURL: URL) -> [URL] {
        let directory = databaseURL.deletingLastPathComponent()
        let baseName = databaseURL.lastPathComponent
        return [
            databaseURL,
            directory.appendingPathComponent("\(baseName)-wal"),
            directory.appendingPathComponent("\(baseName)-shm"),
            directory.appendingPathComponent("\(baseName)-journal")
        ]
    }

    private func event(from row: [String: SQLiteValue]) -> LocationEvent {
        LocationEvent(
            id: row["id"]?.int64,
            latitude: row["latitude"]?.double ?? 0,
            longitude: row["longitude"]?.double ?? 0,
            horizontalAccuracy: row["horizontalAccuracy"]?.double ?? -1,
            verticalAccuracy: row["verticalAccuracy"]?.double ?? -1,
            altitude: row["altitude"]?.double ?? 0,
            course: row["course"]?.double ?? -1,
            speed: row["speed"]?.double ?? -1,
            timestamp: Date(timeIntervalSinceReferenceDate: row["timestamp"]?.double ?? 0),
            localizedDate: row["localizedDate"]?.string,
            source: EventSource(rawValue: Int(row["source"]?.int64 ?? 5)) ?? .invalid,
            geolocationID: row["geolocationID"]?.int64,
            note: row["note"]?.string ?? "",
            tags: row["tags"]?.string ?? "",
            externalReference: row["externalReference"]?.string ?? "",
            photoFilename: row["photoFilename"]?.string ?? "",
            isDemo: (row["isDemo"]?.int64 ?? 0) != 0,
            solarPeriod: SolarPeriod(rawValue: row["solar_period"]?.string ?? "") ?? .unknown,
            solarPeriodPercent: row["solar_period_percent"]?.double,
            solarPeriodCalculatedAt: row["solar_period_calculated_at"]?.double.map { Date(timeIntervalSinceReferenceDate: $0) }
        )
    }

    private func event(fromJoined row: [String: SQLiteValue]) -> LocationEvent {
        LocationEvent(
            id: row["event_id"]?.int64,
            latitude: row["event_latitude"]?.double ?? 0,
            longitude: row["event_longitude"]?.double ?? 0,
            horizontalAccuracy: row["event_horizontalAccuracy"]?.double ?? -1,
            verticalAccuracy: row["event_verticalAccuracy"]?.double ?? -1,
            altitude: row["event_altitude"]?.double ?? 0,
            course: row["event_course"]?.double ?? -1,
            speed: row["event_speed"]?.double ?? -1,
            timestamp: Date(timeIntervalSinceReferenceDate: row["event_timestamp"]?.double ?? 0),
            localizedDate: row["event_localizedDate"]?.string,
            source: EventSource(rawValue: Int(row["event_source"]?.int64 ?? 5)) ?? .invalid,
            geolocationID: row["event_geolocationID"]?.int64,
            note: row["event_note"]?.string ?? "",
            tags: row["event_tags"]?.string ?? "",
            externalReference: row["event_externalReference"]?.string ?? "",
            photoFilename: row["event_photoFilename"]?.string ?? "",
            isDemo: (row["event_isDemo"]?.int64 ?? 0) != 0,
            solarPeriod: SolarPeriod(rawValue: row["event_solar_period"]?.string ?? "") ?? .unknown,
            solarPeriodPercent: row["event_solar_period_percent"]?.double,
            solarPeriodCalculatedAt: row["event_solar_period_calculated_at"]?.double.map { Date(timeIntervalSinceReferenceDate: $0) }
        )
    }

    private func geolocation(from row: [String: SQLiteValue]) -> Geolocation {
        Geolocation(
            id: row["id"]?.int64,
            latitude: row["latitude"]?.double ?? 0,
            longitude: row["longitude"]?.double ?? 0,
            radius: row["radius"]?.double ?? 0,
            identifier: row["identifier"]?.string ?? "",
            horizontalAccuracy: row["horizontalAccuracy"]?.double ?? -1,
            verticalAccuracy: row["verticalAccuracy"]?.double ?? -1,
            altitude: row["altitude"]?.double ?? 0,
            timestamp: (row["timestamp"]?.double).map { Date(timeIntervalSinceReferenceDate: $0) },
            minLatitude: row["minLatitude"]?.double,
            maxLatitude: row["maxLatitude"]?.double,
            minLongitude: row["minLongitude"]?.double,
            maxLongitude: row["maxLongitude"]?.double,
            timeZoneIdentifier: row["timeZoneIdentifier"]?.string ?? "",
            name: row["name"]?.string ?? "",
            subThoroughfare: row["subThoroughfare"]?.string ?? "",
            thoroughfare: row["thoroughfare"]?.string ?? "",
            subLocality: row["subLocality"]?.string ?? "",
            locality: row["locality"]?.string ?? "",
            subAdministrativeArea: row["subAdministrativeArea"]?.string ?? "",
            administrativeArea: row["administrativeArea"]?.string ?? "",
            postalCode: row["postalCode"]?.string ?? "",
            isoCountryCode: row["isoCountryCode"]?.string ?? "",
            country: row["country"]?.string ?? "",
            inlandWater: row["inlandWater"]?.string ?? "",
            ocean: row["ocean"]?.string ?? "",
            areasOfInterest: (row["areasOfInterest"]?.string ?? "").components(separatedBy: "|||TRAVELS|||")
        )
    }

    private func optionalString(_ value: String?) -> SQLiteValue {
        guard let value else { return .null }
        return .text(value)
    }

    private func optionalInt(_ value: Int64?) -> SQLiteValue {
        guard let value else { return .null }
        return .integer(value)
    }

    private func optionalDouble(_ value: Double?) -> SQLiteValue {
        guard let value else { return .null }
        return .real(value)
    }

    private func optionalDate(_ value: Date?) -> SQLiteValue {
        guard let value else { return .null }
        return .real(value.timeIntervalSinceReferenceDate)
    }

    private func solarStorageValues(
        for event: LocationEvent,
        timeZoneOverride: TimeZone? = nil,
        calculatedAt: Date = Date()
    ) -> (period: SolarPeriod, percent: Double?, calculatedAt: Date) {
        if timeZoneOverride == nil, event.solarPeriod != .unknown {
            return (event.solarPeriod, event.solarPeriodPercent, event.solarPeriodCalculatedAt ?? calculatedAt)
        }

        let timeZone: TimeZone?
        if let timeZoneOverride {
            timeZone = timeZoneOverride
        } else if let geolocationID = event.geolocationID,
                  let geolocation = try? geolocation(id: geolocationID),
                  let resolvedTimeZone = TimeZone(identifier: geolocation.timeZoneIdentifier) {
            timeZone = resolvedTimeZone
        } else {
            timeZone = nil
        }
        guard let timeZone else {
            return (.unknown, nil, calculatedAt)
        }
        let result = SolarTwilight.solarPeriodResult(
            at: event.timestamp,
            latitude: event.latitude,
            longitude: event.longitude,
            timeZone: timeZone
        )
        return (result.period, result.percent, calculatedAt)
    }

    private func refreshSolarPeriodIfNeeded(
        for event: LocationEvent,
        geolocation: Geolocation? = nil
    ) throws -> LocationEvent {
        guard event.solarPeriod == .unknown else {
            return event
        }

        let resolvedGeolocation: Geolocation?
        if let geolocation {
            resolvedGeolocation = geolocation
        } else if let geolocationID = event.geolocationID {
            resolvedGeolocation = try self.geolocation(id: geolocationID)
        } else {
            resolvedGeolocation = nil
        }
        guard let timeZoneIdentifier = resolvedGeolocation?.timeZoneIdentifier,
              let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            return event
        }

        let solar = solarStorageValues(for: event, timeZoneOverride: timeZone)
        guard solar.period != .unknown || solar.percent != nil else {
            return event
        }

        guard let eventID = event.id else {
            return event
        }

        var refreshedEvent = event
        refreshedEvent.solarPeriod = solar.period
        refreshedEvent.solarPeriodPercent = solar.percent
        refreshedEvent.solarPeriodCalculatedAt = solar.calculatedAt
        try replaceEvent(eventID: eventID, with: refreshedEvent)
        return refreshedEvent
    }

    private func event(id: Int64) throws -> LocationEvent? {
        let rows = try database.query("SELECT * FROM events WHERE id = ?", parameters: [.integer(id)])
        guard let row = rows.first else { return nil }
        let event = event(from: row)
        return try refreshSolarPeriodIfNeeded(for: event)
    }

    private func dayHasVisibleNonDemoEvents(day: String, includeDemo: Bool) throws -> Bool {
        let rows = try database.query(
            """
            SELECT 1
            FROM events
            WHERE localizedDate = ? AND (? = 1 OR isDemo = 0) AND isDemo = 0
            LIMIT 1
            """,
            parameters: [
                .text(day),
                .integer(includeDemo ? 1 : 0)
            ]
        )
        return !rows.isEmpty
    }

    private func nonAny(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty, value != "Any" else {
            return nil
        }
        return value
    }

    private func ensureColumnExists(table: String, column: String, definition: String) throws {
        let rows = try database.query("PRAGMA table_info(\(table))")
        guard !rows.contains(where: { $0["name"]?.string == column }) else {
            return
        }
        try database.execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
    }
}
