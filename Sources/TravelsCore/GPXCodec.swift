// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public struct GPXTrackPoint: Equatable, Sendable {
    public var event: LocationEvent
    public var geolocation: Geolocation?

    public init(event: LocationEvent, geolocation: Geolocation? = nil) {
        self.event = event
        self.geolocation = geolocation
    }
}

public struct GPXImportResult: Equatable, Sendable {
    public var events: [LocationEvent]
    public var trackPoints: [GPXTrackPoint]
    public var skippedInvalidPoints: Int

    public init(events: [LocationEvent], trackPoints: [GPXTrackPoint] = [], skippedInvalidPoints: Int = 0) {
        self.events = events
        self.trackPoints = trackPoints
        self.skippedInvalidPoints = skippedInvalidPoints
    }
}

public enum GPXImporter {
    public static func parse(data: Data) throws -> GPXImportResult {
        let parser = GPXTrackParser(data: data)
        return try parser.parse()
    }

    public static func parse(url: URL) throws -> GPXImportResult {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try parse(data: Data(contentsOf: url))
    }
}

public enum GPXExporter {
    public static func export(events: [EventDetail], title: String = "Travels life tracker log") throws -> String {
        guard !events.isEmpty else { throw TravelsError.emptyExport }
        let bounds = coordinateBounds(for: events)
        let formatter = TravelsDateTools.gpxFormatter()
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Travels - life tracking" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://www.topografix.com/GPX/1/1" xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
          <metadata>
            <name>\(escape(title))</name>
            <time>\(formatter.string(from: Date()))</time>
            <bounds minlat="\(bounds.minLat)" maxlat="\(bounds.maxLat)" minlon="\(bounds.minLon)" maxlon="\(bounds.maxLon)"/>
          </metadata>
          <trk>
            <trkseg>
        """

        for detail in events {
            let event = detail.event
            let geolocation = detail.geolocation
            xml += "\n      <trkpt lat=\"\(event.latitude)\" lon=\"\(event.longitude)\">"
            xml += "\n        <time>\(formatter.string(from: event.timestamp))</time>"
            xml += "\n        <heading>\(event.course)</heading>"
            xml += "\n        <speed>\(event.speed)</speed>"
            if event.horizontalAccuracy >= 0 {
                xml += "\n        <horizontalAccuracy>\(event.horizontalAccuracy)</horizontalAccuracy>"
            }
            if let timeZone = geolocation?.timeZoneIdentifier, !timeZone.isEmpty {
                xml += "\n        <timeZone>\(escape(timeZone))</timeZone>"
            }
            append("name", geolocation?.name, to: &xml)
            append("subThoroughfare", geolocation?.subThoroughfare, to: &xml)
            append("thoroughfare", geolocation?.thoroughfare, to: &xml)
            append("subLocality", geolocation?.subLocality, to: &xml)
            append("locality", geolocation?.locality, to: &xml)
            append("subAdministrativeArea", geolocation?.subAdministrativeArea, to: &xml)
            append("administrativeArea", geolocation?.administrativeArea, to: &xml)
            append("postalCode", geolocation?.postalCode, to: &xml)
            append("isoCountryCode", geolocation?.isoCountryCode, to: &xml)
            append("country", geolocation?.country, to: &xml)
            append("inlandWater", geolocation?.inlandWater, to: &xml)
            append("ocean", geolocation?.ocean, to: &xml)
            let areas = Geolocation.normalizedAreasOfInterest(geolocation?.areasOfInterest ?? []).joined(separator: "|||TRAVELS|||")
            append("areasOfInterest", areas, to: &xml)
            append("note", event.note, to: &xml)
            xml += "\n      </trkpt>"
        }

        xml += """

            </trkseg>
          </trk>
        </gpx>
        """
        return xml
    }

    private static func append(_ name: String, _ value: String?, to xml: inout String) {
        guard let value, !value.isEmpty else { return }
        xml += "\n        <\(name)>\(escape(value))</\(name)>"
    }

    private static func coordinateBounds(for events: [EventDetail]) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        var minLat = events[0].event.latitude
        var maxLat = events[0].event.latitude
        var minLon = events[0].event.longitude
        var maxLon = events[0].event.longitude
        for detail in events {
            minLat = min(minLat, detail.event.latitude)
            maxLat = max(maxLat, detail.event.latitude)
            minLon = min(minLon, detail.event.longitude)
            maxLon = max(maxLon, detail.event.longitude)
        }
        return (minLat, maxLat, minLon, maxLon)
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

private final class GPXTrackParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var currentPoint: [String: String]?
    private var currentElement = ""
    private var currentText = ""
    private var trackPoints: [GPXTrackPoint] = []
    private var skipped = 0
    private let formatter = ISO8601DateFormatter()

    init(data: Data) {
        parser = XMLParser(data: data)
        super.init()
        formatter.formatOptions = [.withInternetDateTime]
        parser.delegate = self
    }

    func parse() throws -> GPXImportResult {
        guard parser.parse() else {
            throw TravelsError.invalidGPX(parser.parserError?.localizedDescription ?? "Unable to parse GPX")
        }
        return GPXImportResult(events: trackPoints.map(\.event), trackPoints: trackPoints, skippedInvalidPoints: skipped)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
        if elementName == "trkpt" {
            currentPoint = attributeDict
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard var point = currentPoint else { return }
        if elementName == "trkpt" {
            if let trackPoint = trackPoint(from: point) {
                trackPoints.append(trackPoint)
            } else {
                skipped += 1
            }
            currentPoint = nil
        } else if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            point[elementName] = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            currentPoint = point
        }
    }

    private func trackPoint(from point: [String: String]) -> GPXTrackPoint? {
        guard
            let latitude = Double(point["lat"] ?? ""),
            let longitude = Double(point["lon"] ?? ""),
            (-90...90).contains(latitude),
            (-180...180).contains(longitude),
            let time = point["time"],
            let timestamp = parseTimestamp(time)
        else {
            return nil
        }

        let event = LocationEvent(
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracy: Double(point["horizontalAccuracy"] ?? "") ?? -1,
            course: Double(point["heading"] ?? "") ?? -1,
            speed: Double(point["speed"] ?? "") ?? -1,
            timestamp: timestamp,
            localizedDate: TravelsDateTools.localizedDayString(for: timestamp, timeZoneIdentifier: point["timeZone"]),
            source: .imported,
            note: point["note"] ?? ""
        )
        let geolocation = geolocation(from: point, event: event)
        return GPXTrackPoint(event: event, geolocation: geolocation)
    }

    private func geolocation(from point: [String: String], event: LocationEvent) -> Geolocation? {
        let areasOfInterest = point["areasOfInterest"].map { raw -> [String] in
            guard !raw.isEmpty else { return [] }
            return raw.components(separatedBy: "|||TRAVELS|||")
        } ?? []

        let hasMeaningfulMetadata =
            !(point["timeZone"] ?? "").isEmpty ||
            !(point["name"] ?? "").isEmpty ||
            !(point["subThoroughfare"] ?? "").isEmpty ||
            !(point["thoroughfare"] ?? "").isEmpty ||
            !(point["subLocality"] ?? "").isEmpty ||
            !(point["locality"] ?? "").isEmpty ||
            !(point["subAdministrativeArea"] ?? "").isEmpty ||
            !(point["administrativeArea"] ?? "").isEmpty ||
            !(point["postalCode"] ?? "").isEmpty ||
            !(point["isoCountryCode"] ?? "").isEmpty ||
            !(point["country"] ?? "").isEmpty ||
            !(point["inlandWater"] ?? "").isEmpty ||
            !(point["ocean"] ?? "").isEmpty ||
            !areasOfInterest.isEmpty

        guard hasMeaningfulMetadata else { return nil }

        return Geolocation(
            latitude: event.latitude,
            longitude: event.longitude,
            radius: max(event.horizontalAccuracy, 0),
            identifier: "\(event.timestamp.timeIntervalSinceReferenceDate)-\(event.latitude)-\(event.longitude)",
            horizontalAccuracy: event.horizontalAccuracy,
            verticalAccuracy: event.verticalAccuracy,
            altitude: event.altitude,
            timestamp: event.timestamp,
            minLatitude: event.latitude,
            maxLatitude: event.latitude,
            minLongitude: event.longitude,
            maxLongitude: event.longitude,
            timeZoneIdentifier: point["timeZone"] ?? "",
            name: point["name"] ?? "",
            subThoroughfare: point["subThoroughfare"] ?? "",
            thoroughfare: point["thoroughfare"] ?? "",
            subLocality: point["subLocality"] ?? "",
            locality: point["locality"] ?? "",
            subAdministrativeArea: point["subAdministrativeArea"] ?? "",
            administrativeArea: point["administrativeArea"] ?? "",
            postalCode: point["postalCode"] ?? "",
            isoCountryCode: point["isoCountryCode"] ?? "",
            country: point["country"] ?? "",
            inlandWater: point["inlandWater"] ?? "",
            ocean: point["ocean"] ?? "",
            areasOfInterest: areasOfInterest
        )
    }

    private func parseTimestamp(_ value: String) -> Date? {
        if let isoDate = formatter.date(from: value) {
            return isoDate
        }
        if let seconds = Double(value) {
            return Date(timeIntervalSinceReferenceDate: seconds)
        }
        return nil
    }
}
