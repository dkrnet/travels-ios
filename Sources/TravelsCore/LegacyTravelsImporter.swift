// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public struct LegacyImportSummary: Equatable, Sendable {
    public var importedEvents: Int
    public var skippedDuplicates: Int
    public var importedGeolocations: Int
    public var importedSettings: Int

    public init(importedEvents: Int = 0, skippedDuplicates: Int = 0, importedGeolocations: Int = 0, importedSettings: Int = 0) {
        self.importedEvents = importedEvents
        self.skippedDuplicates = skippedDuplicates
        self.importedGeolocations = importedGeolocations
        self.importedSettings = importedSettings
    }
}

public final class LegacyTravelsImporter: @unchecked Sendable {
    private let destination: TravelsStore

    public init(destination: TravelsStore) {
        self.destination = destination
    }

    public func importIfPresent(in applicationSupportURL: URL) throws -> LegacyImportSummary {
        let legacyURL = applicationSupportURL.appendingPathComponent("travels.sqlite")
        guard FileManager.default.fileExists(atPath: legacyURL.path) else {
            throw TravelsError.legacyDatabaseNotFound
        }
        return try importDatabase(at: legacyURL)
    }

    public func importDatabase(at url: URL) throws -> LegacyImportSummary {
        let legacy = try SQLiteDatabase(path: url.path)
        var summary = LegacyImportSummary()
        var geolocationMap: [Int64: Int64] = [:]

        let legacyGeolocations = try legacy.query("SELECT * FROM geolocations")
        for row in legacyGeolocations {
            let oldID = row["geoID"]?.int64
            let geolocation = Geolocation(
                latitude: row["geoLatitude"]?.double ?? 0,
                longitude: row["geoLongitude"]?.double ?? 0,
                radius: row["geoRadius"]?.double ?? 0,
                identifier: row["geoIdentifier"]?.string ?? "",
                horizontalAccuracy: row["geoHAccuracy"]?.double ?? -1,
                verticalAccuracy: row["geoVAccuracy"]?.double ?? -1,
                altitude: row["geoAltitude"]?.double ?? 0,
                timestamp: (row["geoTimestamp"]?.double).map { Date(timeIntervalSinceReferenceDate: $0) },
                minLatitude: row["geoMinLatitude"]?.double,
                maxLatitude: row["geoMaxLatitude"]?.double,
                minLongitude: row["geoMinLongitude"]?.double,
                maxLongitude: row["geoMaxLongitude"]?.double,
                timeZoneIdentifier: row["geoTimezone"]?.string ?? "",
                name: row["geoName"]?.string ?? "",
                subThoroughfare: row["geoSubThoroughfare"]?.string ?? "",
                thoroughfare: row["geothoroughfare"]?.string ?? "",
                subLocality: row["geoSubLocality"]?.string ?? "",
                locality: row["geoLocality"]?.string ?? "",
                subAdministrativeArea: row["geoSubAdministrativeArea"]?.string ?? "",
                administrativeArea: row["geoAdministrativeArea"]?.string ?? "",
                postalCode: row["geoPostalCode"]?.string ?? "",
                isoCountryCode: row["geoISOCountryCode"]?.string ?? "",
                country: row["geoCountry"]?.string ?? "",
                inlandWater: row["geoInlandWater"]?.string ?? "",
                ocean: row["geoOcean"]?.string ?? "",
                areasOfInterest: (row["geoAreasOfInterest"]?.string ?? "").components(separatedBy: "|||TRAVELS|||")
            )
            let newID = try destination.saveGeolocation(geolocation)
            if let oldID {
                geolocationMap[oldID] = newID
            }
            summary.importedGeolocations += 1
        }

        let legacyEvents = try legacy.query("SELECT * FROM events ORDER BY eventTimestamp ASC")
        for row in legacyEvents {
            let oldGeoID = row["eventGeoID"]?.int64
            let mappedGeoID = oldGeoID.flatMap { geolocationMap[$0] }
            let source = EventSource(rawValue: Int(row["eventSource"]?.int64 ?? 5)) ?? .invalid
            let event = LocationEvent(
                latitude: row["eventLatitude"]?.double ?? 0,
                longitude: row["eventLongitude"]?.double ?? 0,
                horizontalAccuracy: row["eventAccuracy"]?.double ?? -1,
                verticalAccuracy: -1,
                altitude: 0,
                course: row["eventCourse"]?.double ?? -1,
                speed: row["eventSpeed"]?.double ?? -1,
                timestamp: Date(timeIntervalSinceReferenceDate: row["eventTimestamp"]?.double ?? 0),
                localizedDate: row["eventLocalizedDate"]?.string,
                source: source,
                geolocationID: mappedGeoID,
                note: row["eventNote"]?.string ?? "",
                tags: row["eventTags"]?.string ?? "",
                externalReference: row["eventExtRef"]?.string ?? ""
            )
            if try destination.findDuplicate(event) == nil {
                _ = try destination.saveEvent(event)
                summary.importedEvents += 1
            } else {
                summary.skippedDuplicates += 1
            }
        }

        let settings = try legacy.query("SELECT * FROM settings")
        for row in settings {
            guard let key = row["settingName"]?.string else { continue }
            let value = row["settingTextValue"]?.string
                ?? row["settingBoolValue"]?.string
                ?? row["settingIntValue"]?.string
                ?? row["settingDoubleValue"]?.string
                ?? ""
            try destination.setSetting("legacy.\(key)", value: value)
            summary.importedSettings += 1
        }

        try destination.setSetting("migration.legacyTravelsSQLite.complete", value: "true")
        try destination.setSetting("migration.legacyTravelsSQLite.date", value: ISO8601DateFormatter().string(from: Date()))
        return summary
    }
}
