// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public enum EventSource: Int, Codable, CaseIterable, Sendable {
    case locationServices = 1
    case imported = 2
    case photo = 3
    case manual = 4
    case invalid = 5
    case simulated = 6

    public var displayName: String {
        switch self {
        case .locationServices: "Location Services"
        case .imported: "Imported"
        case .photo: "Photo"
        case .manual: "Manual"
        case .invalid: "Invalid"
        case .simulated: "Simulated"
        }
    }
}

public struct LocationEvent: Identifiable, Codable, Equatable, Sendable {
    public var id: Int64?
    public var latitude: Double
    public var longitude: Double
    public var horizontalAccuracy: Double
    public var verticalAccuracy: Double
    public var altitude: Double
    public var course: Double
    public var speed: Double
    public var timestamp: Date
    public var localizedDate: String?
    public var source: EventSource
    public var geolocationID: Int64?
    public var note: String
    public var tags: String
    public var externalReference: String
    public var photoFilename: String

    public init(
        id: Int64? = nil,
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double = -1,
        verticalAccuracy: Double = -1,
        altitude: Double = 0,
        course: Double = -1,
        speed: Double = -1,
        timestamp: Date,
        localizedDate: String? = nil,
        source: EventSource,
        geolocationID: Int64? = nil,
        note: String = "",
        tags: String = "",
        externalReference: String = "",
        photoFilename: String = ""
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.altitude = altitude
        self.course = course
        self.speed = speed
        self.timestamp = timestamp
        self.localizedDate = localizedDate
        self.source = source
        self.geolocationID = geolocationID
        self.note = note
        self.tags = tags
        self.externalReference = externalReference
        self.photoFilename = photoFilename
    }
}

public struct Geolocation: Identifiable, Codable, Equatable, Sendable {
    public var id: Int64?
    public var latitude: Double
    public var longitude: Double
    public var radius: Double
    public var identifier: String
    public var horizontalAccuracy: Double
    public var verticalAccuracy: Double
    public var altitude: Double
    public var timestamp: Date?
    public var minLatitude: Double?
    public var maxLatitude: Double?
    public var minLongitude: Double?
    public var maxLongitude: Double?
    public var timeZoneIdentifier: String
    public var name: String
    public var subThoroughfare: String
    public var thoroughfare: String
    public var subLocality: String
    public var locality: String
    public var subAdministrativeArea: String
    public var administrativeArea: String
    public var postalCode: String
    public var isoCountryCode: String
    public var country: String
    public var inlandWater: String
    public var ocean: String
    public var areasOfInterest: [String]

    public init(
        id: Int64? = nil,
        latitude: Double = 0,
        longitude: Double = 0,
        radius: Double = 0,
        identifier: String = "",
        horizontalAccuracy: Double = -1,
        verticalAccuracy: Double = -1,
        altitude: Double = 0,
        timestamp: Date? = nil,
        minLatitude: Double? = nil,
        maxLatitude: Double? = nil,
        minLongitude: Double? = nil,
        maxLongitude: Double? = nil,
        timeZoneIdentifier: String = "",
        name: String = "",
        subThoroughfare: String = "",
        thoroughfare: String = "",
        subLocality: String = "",
        locality: String = "",
        subAdministrativeArea: String = "",
        administrativeArea: String = "",
        postalCode: String = "",
        isoCountryCode: String = "",
        country: String = "",
        inlandWater: String = "",
        ocean: String = "",
        areasOfInterest: [String] = []
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.identifier = identifier
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.altitude = altitude
        self.timestamp = timestamp
        self.minLatitude = minLatitude
        self.maxLatitude = maxLatitude
        self.minLongitude = minLongitude
        self.maxLongitude = maxLongitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.name = name
        self.subThoroughfare = subThoroughfare
        self.thoroughfare = thoroughfare
        self.subLocality = subLocality
        self.locality = locality
        self.subAdministrativeArea = subAdministrativeArea
        self.administrativeArea = administrativeArea
        self.postalCode = postalCode
        self.isoCountryCode = isoCountryCode
        self.country = country
        self.inlandWater = inlandWater
        self.ocean = ocean
        self.areasOfInterest = Geolocation.normalizedAreasOfInterest(areasOfInterest)
    }

    public static func normalizedAreasOfInterest(_ values: [String]) -> [String] {
        Array(Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }
}

public struct EventDetail: Identifiable, Equatable, Sendable {
    public var event: LocationEvent
    public var geolocation: Geolocation?

    public var id: Int64? { event.id }

    public init(event: LocationEvent, geolocation: Geolocation?) {
        self.event = event
        self.geolocation = geolocation
    }
}

public struct SearchCriteria: Equatable, Sendable {
    public var term: String
    public var startDate: Date?
    public var endDate: Date?
    public var hasNote: Bool
    public var country: String?
    public var administrativeArea: String?
    public var subAdministrativeArea: String?
    public var locality: String?
    public var bodyOfWater: String?
    public var source: EventSource?

    public init(
        term: String = "",
        startDate: Date? = nil,
        endDate: Date? = nil,
        hasNote: Bool = false,
        country: String? = nil,
        administrativeArea: String? = nil,
        subAdministrativeArea: String? = nil,
        locality: String? = nil,
        bodyOfWater: String? = nil,
        source: EventSource? = nil
    ) {
        self.term = term
        self.startDate = startDate
        self.endDate = endDate
        self.hasNote = hasNote
        self.country = country
        self.administrativeArea = administrativeArea
        self.subAdministrativeArea = subAdministrativeArea
        self.locality = locality
        self.bodyOfWater = bodyOfWater
        self.source = source
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var autoAddLocations: Bool
    public var backgroundLocationEnabled: Bool
    public var resolveAddresses: Bool
    public var resolveMissingAddresses: Bool
    public var includePreviousDayContext: Bool
    public var includeDemoData: Bool
    public var requireAuthentication: Bool
    public var preferListView: Bool
    public var poweredUpdateDistanceMeters: Int
    public var batteryUpdateDistanceMeters: Int

    public init(
        autoAddLocations: Bool = true,
        backgroundLocationEnabled: Bool = true,
        resolveAddresses: Bool = true,
        resolveMissingAddresses: Bool = true,
        includePreviousDayContext: Bool = true,
        includeDemoData: Bool = true,
        requireAuthentication: Bool = false,
        preferListView: Bool = false,
        poweredUpdateDistanceMeters: Int = 500,
        batteryUpdateDistanceMeters: Int = 1_000
    ) {
        self.autoAddLocations = autoAddLocations
        self.backgroundLocationEnabled = backgroundLocationEnabled
        self.resolveAddresses = resolveAddresses
        self.resolveMissingAddresses = resolveMissingAddresses
        self.includePreviousDayContext = includePreviousDayContext
        self.includeDemoData = includeDemoData
        self.requireAuthentication = requireAuthentication
        self.preferListView = preferListView
        self.poweredUpdateDistanceMeters = poweredUpdateDistanceMeters
        self.batteryUpdateDistanceMeters = batteryUpdateDistanceMeters
    }

    private enum CodingKeys: String, CodingKey {
        case autoAddLocations
        case backgroundLocationEnabled
        case resolveAddresses
        case resolveMissingAddresses
        case includePreviousDayContext
        case includeDemoData
        case requireAuthentication
        case preferListView
        case poweredUpdateDistanceMeters
        case batteryUpdateDistanceMeters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.autoAddLocations = try container.decodeIfPresent(Bool.self, forKey: .autoAddLocations) ?? true
        self.backgroundLocationEnabled = try container.decodeIfPresent(Bool.self, forKey: .backgroundLocationEnabled) ?? true
        self.resolveAddresses = try container.decodeIfPresent(Bool.self, forKey: .resolveAddresses) ?? true
        self.resolveMissingAddresses = try container.decodeIfPresent(Bool.self, forKey: .resolveMissingAddresses) ?? true
        self.includePreviousDayContext = try container.decodeIfPresent(Bool.self, forKey: .includePreviousDayContext) ?? true
        self.includeDemoData = try container.decodeIfPresent(Bool.self, forKey: .includeDemoData) ?? true
        self.requireAuthentication = try container.decodeIfPresent(Bool.self, forKey: .requireAuthentication) ?? false
        self.preferListView = try container.decodeIfPresent(Bool.self, forKey: .preferListView) ?? false
        self.poweredUpdateDistanceMeters = try container.decodeIfPresent(Int.self, forKey: .poweredUpdateDistanceMeters) ?? 500
        self.batteryUpdateDistanceMeters = try container.decodeIfPresent(Int.self, forKey: .batteryUpdateDistanceMeters) ?? 1_000
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(autoAddLocations, forKey: .autoAddLocations)
        try container.encode(backgroundLocationEnabled, forKey: .backgroundLocationEnabled)
        try container.encode(resolveAddresses, forKey: .resolveAddresses)
        try container.encode(resolveMissingAddresses, forKey: .resolveMissingAddresses)
        try container.encode(includePreviousDayContext, forKey: .includePreviousDayContext)
        try container.encode(includeDemoData, forKey: .includeDemoData)
        try container.encode(requireAuthentication, forKey: .requireAuthentication)
        try container.encode(preferListView, forKey: .preferListView)
        try container.encode(poweredUpdateDistanceMeters, forKey: .poweredUpdateDistanceMeters)
        try container.encode(batteryUpdateDistanceMeters, forKey: .batteryUpdateDistanceMeters)
    }
}

public enum TravelsError: Error, Equatable, LocalizedError, Sendable {
    case databaseOpenFailed(String)
    case databaseExecutionFailed(String)
    case invalidGPX(String)
    case emptyExport
    case legacyDatabaseNotFound
    case legacyImportFailed(String)
    case eventNotFound

    public var errorDescription: String? {
        switch self {
        case .databaseOpenFailed(let message): "Unable to open database: \(message)"
        case .databaseExecutionFailed(let message): "Database operation failed: \(message)"
        case .invalidGPX(let message): "Invalid GPX: \(message)"
        case .emptyExport: "Select at least one event to export."
        case .legacyDatabaseNotFound: "No legacy Travels database was found."
        case .legacyImportFailed(let message): "Legacy import failed: \(message)"
        case .eventNotFound: "The requested event was not found."
        }
    }
}
