// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.

import Foundation

public enum PhotoImportMode: String, Codable, CaseIterable, Sendable {
    case photoAndLocation
    case locationOnly

    public var displayName: String {
        switch self {
        case .photoAndLocation:
            return "Import Photo and Location"
        case .locationOnly:
            return "Import Location Only"
        }
    }
}

public struct PhotoImportMetadata: Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double
    public var horizontalAccuracy: Double
    public var verticalAccuracy: Double
    public var altitude: Double
    public var course: Double
    public var speed: Double
    public var timestamp: Date

    public init(
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double,
        verticalAccuracy: Double,
        altitude: Double,
        course: Double,
        speed: Double,
        timestamp: Date
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.altitude = altitude
        self.course = course
        self.speed = speed
        self.timestamp = timestamp
    }
}

public extension LocationEvent {
    static func photoImport(
        metadata: PhotoImportMetadata,
        assetIdentifier: String,
        note: String = "",
        mode: PhotoImportMode,
        copiedPhotoFilename: String = ""
    ) -> LocationEvent {
        LocationEvent(
            latitude: metadata.latitude,
            longitude: metadata.longitude,
            horizontalAccuracy: metadata.horizontalAccuracy,
            verticalAccuracy: metadata.verticalAccuracy,
            altitude: metadata.altitude,
            course: metadata.course,
            speed: metadata.speed,
            timestamp: metadata.timestamp,
            localizedDate: TravelsDateTools.localizedDayString(for: metadata.timestamp, timeZoneIdentifier: nil),
            source: .photo,
            note: note,
            tags: "",
            externalReference: assetIdentifier,
            photoFilename: mode == .photoAndLocation ? copiedPhotoFilename : ""
        )
    }
}
