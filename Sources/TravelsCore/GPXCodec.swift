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
    private static let travelsNamespace = "https://github.com/dkrnet/travels-ios/gpx/extensions/1"

    public static func export(events: [EventDetail], title: String = "Travels life tracker log") throws -> String {
        guard !events.isEmpty else { throw TravelsError.emptyExport }
        let bounds = coordinateBounds(for: events)
        let formatter = TravelsDateTools.gpxFormatter()
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Travels - life tracking" xmlns="http://www.topografix.com/GPX/1/1" xmlns:travels="\(travelsNamespace)" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
          <metadata>
            <name>\(escape(title))</name>
            <time>\(formatter.string(from: Date()))</time>
            <bounds minlat="\(bounds.minLat)" maxlat="\(bounds.maxLat)" minlon="\(bounds.minLon)" maxlon="\(bounds.maxLon)"/>
          </metadata>
          <trk>
            <name>\(escape(title))</name>
            <trkseg>
        """

        for detail in events {
            appendTrackPoint(detail, formatter: formatter, to: &xml)
        }

        xml += """

            </trkseg>
          </trk>
        </gpx>
        """
        return xml
    }

    private static func appendTrackPoint(_ detail: EventDetail, formatter: ISO8601DateFormatter, to xml: inout String) {
        let event = detail.event
        let geolocation = detail.geolocation

        xml += "\n      <trkpt lat=\"\(event.latitude)\" lon=\"\(event.longitude)\">"
        if event.altitude != 0 || event.verticalAccuracy >= 0 {
            xml += "\n        <ele>\(event.altitude)</ele>"
        }
        xml += "\n        <time>\(formatter.string(from: event.timestamp))</time>"
        appendStandardText("name", geolocation?.name, to: &xml)
        appendStandardText("cmt", event.note, to: &xml)
        appendStandardText("src", event.source.displayName, to: &xml)

        var eventExtension = ""
        appendTravelsText("horizontalAccuracyMeters", value: event.horizontalAccuracy >= 0 ? String(event.horizontalAccuracy) : nil, to: &eventExtension)
        appendTravelsText("verticalAccuracyMeters", value: event.verticalAccuracy >= 0 ? String(event.verticalAccuracy) : nil, to: &eventExtension)
        appendTravelsText("headingDegrees", value: event.course >= 0 ? String(event.course) : nil, to: &eventExtension)
        appendTravelsText("speedMetersPerSecond", value: event.speed >= 0 ? String(event.speed) : nil, to: &eventExtension)
        appendTravelsText("timeZoneIdentifier", value: geolocation?.timeZoneIdentifier, to: &eventExtension)
        appendTravelsText("localizedDate", value: event.localizedDate, to: &eventExtension)
        appendTravelsText("tags", value: event.tags, to: &eventExtension)
        appendTravelsText("externalReference", value: event.externalReference, to: &eventExtension)
        appendTravelsText("photoFilename", value: event.photoFilename, to: &eventExtension)
        appendTravelsText("isDemo", value: event.isDemo ? "true" : nil, to: &eventExtension)
        appendTravelsText("solarPeriod", value: event.solarPeriod.rawValue, to: &eventExtension)
        appendTravelsText("solarPeriodPercent", value: event.solarPeriodPercent.map { String($0) }, to: &eventExtension)
        appendTravelsText("solarPeriodCalculatedAt", value: event.solarPeriodCalculatedAt.map { formatter.string(from: $0) }, to: &eventExtension)

        var placeExtension = ""
        if let geolocation {
            appendTravelsText("identifier", value: geolocation.identifier, to: &placeExtension)
            appendTravelsText("latitude", value: String(geolocation.latitude), to: &placeExtension)
            appendTravelsText("longitude", value: String(geolocation.longitude), to: &placeExtension)
            appendTravelsText("radiusMeters", value: String(geolocation.radius), to: &placeExtension)
            appendTravelsText("horizontalAccuracyMeters", value: geolocation.horizontalAccuracy >= 0 ? String(geolocation.horizontalAccuracy) : nil, to: &placeExtension)
            appendTravelsText("verticalAccuracyMeters", value: geolocation.verticalAccuracy >= 0 ? String(geolocation.verticalAccuracy) : nil, to: &placeExtension)
            appendTravelsText("altitudeMeters", value: String(geolocation.altitude), to: &placeExtension)
            appendTravelsText("timestamp", value: geolocation.timestamp.map { formatter.string(from: $0) }, to: &placeExtension)
            appendTravelsText("minLatitude", value: geolocation.minLatitude.map { String($0) }, to: &placeExtension)
            appendTravelsText("maxLatitude", value: geolocation.maxLatitude.map { String($0) }, to: &placeExtension)
            appendTravelsText("minLongitude", value: geolocation.minLongitude.map { String($0) }, to: &placeExtension)
            appendTravelsText("maxLongitude", value: geolocation.maxLongitude.map { String($0) }, to: &placeExtension)
            appendTravelsText("timeZoneIdentifier", value: geolocation.timeZoneIdentifier, to: &placeExtension)
            appendTravelsText("name", value: geolocation.name, to: &placeExtension)
            appendTravelsText("subThoroughfare", value: geolocation.subThoroughfare, to: &placeExtension)
            appendTravelsText("thoroughfare", value: geolocation.thoroughfare, to: &placeExtension)
            appendTravelsText("subLocality", value: geolocation.subLocality, to: &placeExtension)
            appendTravelsText("locality", value: geolocation.locality, to: &placeExtension)
            appendTravelsText("subAdministrativeArea", value: geolocation.subAdministrativeArea, to: &placeExtension)
            appendTravelsText("administrativeArea", value: geolocation.administrativeArea, to: &placeExtension)
            appendTravelsText("postalCode", value: geolocation.postalCode, to: &placeExtension)
            appendTravelsText("isoCountryCode", value: geolocation.isoCountryCode, to: &placeExtension)
            appendTravelsText("country", value: geolocation.country, to: &placeExtension)
            appendTravelsText("inlandWater", value: geolocation.inlandWater, to: &placeExtension)
            appendTravelsText("ocean", value: geolocation.ocean, to: &placeExtension)

            if !geolocation.areasOfInterest.isEmpty {
                placeExtension += "\n          <travels:areasOfInterest>"
                for area in geolocation.areasOfInterest {
                    placeExtension += "\n            <travels:areaOfInterest>\(escape(area))</travels:areaOfInterest>"
                }
                placeExtension += "\n          </travels:areasOfInterest>"
            }
        }

        if !eventExtension.isEmpty || !placeExtension.isEmpty {
            xml += "\n        <extensions>"
            if !eventExtension.isEmpty {
                xml += "\n          <travels:event>\(eventExtension)\n          </travels:event>"
            }
            if !placeExtension.isEmpty {
                xml += "\n          <travels:place>\(placeExtension)\n          </travels:place>"
            }
            xml += "\n        </extensions>"
        }

        xml += "\n      </trkpt>"
    }

    private static func appendStandardText(_ name: String, _ value: String?, to xml: inout String) {
        guard let value, !value.isEmpty else { return }
        xml += "\n        <\(name)>\(escape(value))</\(name)>"
    }

    private static func appendTravelsText(_ name: String, value: String?, to xml: inout String, indent: String = "          ") {
        guard let value, !value.isEmpty else { return }
        xml += "\n\(indent)<travels:\(name)>\(escape(value))</travels:\(name)>"
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
    private var elementStack: [String] = []
    private var textStack: [String] = []
    private var currentPoint: GPXTrackPointBuilder?
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
        let name = normalizedElementName(elementName, qualifiedName: qName)
        elementStack.append(name)
        textStack.append("")

        if name == "trkpt" {
            currentPoint = GPXTrackPointBuilder(attributes: attributeDict)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !textStack.isEmpty else { return }
        textStack[textStack.count - 1] += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = normalizedElementName(elementName, qualifiedName: qName)
        let text = textStack.popLast()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        defer {
            _ = elementStack.popLast()
        }

        if let currentPoint, !text.isEmpty {
            currentPoint.consume(text: text, path: elementStack)
        }

        if name == "trkpt" {
            if let trackPoint = currentPoint?.build(using: formatter) {
                trackPoints.append(trackPoint)
            } else {
                skipped += 1
            }
            currentPoint = nil
        }
    }

    private func normalizedElementName(_ elementName: String, qualifiedName: String?) -> String {
        qualifiedName ?? elementName
    }
}

private final class GPXTrackPointBuilder {
    private let attributes: [String: String]

    private var timestampText: String?
    private var altitudeText: String?
    private var noteText: String?
    private var placeNameText: String?
    private var timeZoneIdentifierText: String?
    private var horizontalAccuracyText: String?
    private var verticalAccuracyText: String?
    private var headingText: String?
    private var speedText: String?
    private var localizedDateText: String?
    private var tagsText: String?
    private var externalReferenceText: String?
    private var photoFilenameText: String?
    private var isDemoText: String?
    private var solarPeriodText: String?
    private var solarPeriodPercentText: String?
    private var solarPeriodCalculatedAtText: String?

    private var geolocationIdentifierText: String?
    private var geolocationLatitudeText: String?
    private var geolocationLongitudeText: String?
    private var geolocationRadiusText: String?
    private var geolocationHorizontalAccuracyText: String?
    private var geolocationVerticalAccuracyText: String?
    private var geolocationAltitudeText: String?
    private var geolocationTimestampText: String?
    private var geolocationMinLatitudeText: String?
    private var geolocationMaxLatitudeText: String?
    private var geolocationMinLongitudeText: String?
    private var geolocationMaxLongitudeText: String?
    private var geolocationTimeZoneIdentifierText: String?
    private var geolocationNameText: String?
    private var geolocationSubThoroughfareText: String?
    private var geolocationThoroughfareText: String?
    private var geolocationSubLocalityText: String?
    private var geolocationLocalityText: String?
    private var geolocationSubAdministrativeAreaText: String?
    private var geolocationAdministrativeAreaText: String?
    private var geolocationPostalCodeText: String?
    private var geolocationIsoCountryCodeText: String?
    private var geolocationCountryText: String?
    private var geolocationInlandWaterText: String?
    private var geolocationOceanText: String?
    private var geolocationAreasOfInterest: [String] = []

    init(attributes: [String: String]) {
        self.attributes = attributes
    }

    func consume(text: String, path: [String]) {
        let names = path.map { Self.localName(from: $0) }
        let last = names.last ?? ""
        let containsPlace = names.contains("place")

        // Preserve legacy flat tags, but let namespaced Travels extensions win when both are present.
        switch last {
        case "time":
            timestampText = text
        case "ele":
            altitudeText = text
        case "name" where containsPlace:
            geolocationNameText = text
        case "name":
            placeNameText = text
        case "cmt":
            noteText = text
        case "note":
            noteText = text
        case "src":
            break
        case "heading", "course":
            headingText = text
        case "speed":
            speedText = text
        case "horizontalAccuracy":
            horizontalAccuracyText = text
        case "verticalAccuracy":
            verticalAccuracyText = text
        case "timeZone":
            if containsPlace {
                geolocationTimeZoneIdentifierText = text
            } else {
                timeZoneIdentifierText = text
            }
        case "timeZoneIdentifier":
            if containsPlace {
                geolocationTimeZoneIdentifierText = text
            } else {
                timeZoneIdentifierText = text
            }
        case "localizedDate":
            localizedDateText = text
        case "tags":
            tagsText = text
        case "externalReference":
            externalReferenceText = text
        case "photoFilename":
            photoFilenameText = text
        case "isDemo":
            isDemoText = text
        case "solarPeriod":
            solarPeriodText = text
        case "solarPeriodPercent":
            solarPeriodPercentText = text
        case "solarPeriodCalculatedAt":
            solarPeriodCalculatedAtText = text
        case "twilightPhase":
            solarPeriodText = SolarPeriod(twilightPhase: TwilightPhase(rawValue: text) ?? .none).rawValue
        case "twilightPercent":
            solarPeriodPercentText = text
        case "twilightCalculatedAt":
            solarPeriodCalculatedAtText = text
        case "latitude" where containsPlace:
            geolocationLatitudeText = text
        case "longitude" where containsPlace:
            geolocationLongitudeText = text
        case "radiusMeters", "radius":
            geolocationRadiusText = text
        case "identifier" where containsPlace:
            geolocationIdentifierText = text
        case "horizontalAccuracyMeters" where containsPlace:
            geolocationHorizontalAccuracyText = text
        case "verticalAccuracyMeters" where containsPlace:
            geolocationVerticalAccuracyText = text
        case "altitudeMeters" where containsPlace:
            geolocationAltitudeText = text
        case "timestamp" where containsPlace:
            geolocationTimestampText = text
        case "minLatitude":
            geolocationMinLatitudeText = text
        case "maxLatitude":
            geolocationMaxLatitudeText = text
        case "minLongitude":
            geolocationMinLongitudeText = text
        case "maxLongitude":
            geolocationMaxLongitudeText = text
        case "subThoroughfare":
            geolocationSubThoroughfareText = text
        case "thoroughfare":
            geolocationThoroughfareText = text
        case "subLocality":
            geolocationSubLocalityText = text
        case "locality":
            geolocationLocalityText = text
        case "subAdministrativeArea":
            geolocationSubAdministrativeAreaText = text
        case "administrativeArea":
            geolocationAdministrativeAreaText = text
        case "postalCode":
            geolocationPostalCodeText = text
        case "isoCountryCode":
            geolocationIsoCountryCodeText = text
        case "country":
            geolocationCountryText = text
        case "inlandWater":
            geolocationInlandWaterText = text
        case "ocean":
            geolocationOceanText = text
        case "areaOfInterest":
            geolocationAreasOfInterest.append(text)
        case "areasOfInterest":
            geolocationAreasOfInterest.append(contentsOf: text.components(separatedBy: "|||TRAVELS|||").filter { !$0.isEmpty })
        default:
            break
        }
    }

    func build(using formatter: ISO8601DateFormatter) -> GPXTrackPoint? {
        guard
            let latitude = Double(attributes["lat"] ?? ""),
            let longitude = Double(attributes["lon"] ?? ""),
            (-90...90).contains(latitude),
            (-180...180).contains(longitude),
            let timestampText,
            let timestamp = parseTimestamp(timestampText, formatter: formatter)
        else {
            return nil
        }

        let timeZoneIdentifier = firstNonEmpty(timeZoneIdentifierText, geolocationTimeZoneIdentifierText)
        let localizedDate = firstNonEmpty(localizedDateText, timeZoneIdentifier.map { TravelsDateTools.localizedDayString(for: timestamp, timeZoneIdentifier: $0) })

        let event = LocationEvent(
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracy: parseDouble(firstNonEmpty(horizontalAccuracyText, geolocationHorizontalAccuracyText)),
            verticalAccuracy: parseDouble(firstNonEmpty(verticalAccuracyText, geolocationVerticalAccuracyText)),
            altitude: parseDouble(firstNonEmpty(altitudeText, geolocationAltitudeText), defaultValue: 0),
            course: parseDouble(headingText),
            speed: parseDouble(speedText),
            timestamp: timestamp,
            localizedDate: localizedDate,
            source: .imported,
            note: noteText ?? "",
            tags: tagsText ?? "",
            externalReference: externalReferenceText ?? "",
            photoFilename: photoFilenameText ?? "",
            isDemo: parseBool(isDemoText),
            solarPeriod: parseSolarPeriod(solarPeriodText),
            solarPeriodPercent: parseDouble(solarPeriodPercentText),
            solarPeriodCalculatedAt: parseDate(solarPeriodCalculatedAtText, formatter: formatter)
        )

        return GPXTrackPoint(event: event, geolocation: geolocation(for: event, timeZoneIdentifier: timeZoneIdentifier))
    }

    private func geolocation(for event: LocationEvent, timeZoneIdentifier: String?) -> Geolocation? {
        let areas = Geolocation.normalizedAreasOfInterest(geolocationAreasOfInterest)
        let hasMeaningfulMetadata =
            !(geolocationIdentifierText ?? "").isEmpty ||
            !(timeZoneIdentifier ?? "").isEmpty ||
            !(placeNameText ?? "").isEmpty ||
            !(geolocationNameText ?? "").isEmpty ||
            !(geolocationSubThoroughfareText ?? "").isEmpty ||
            !(geolocationThoroughfareText ?? "").isEmpty ||
            !(geolocationSubLocalityText ?? "").isEmpty ||
            !(geolocationLocalityText ?? "").isEmpty ||
            !(geolocationSubAdministrativeAreaText ?? "").isEmpty ||
            !(geolocationAdministrativeAreaText ?? "").isEmpty ||
            !(geolocationPostalCodeText ?? "").isEmpty ||
            !(geolocationIsoCountryCodeText ?? "").isEmpty ||
            !(geolocationCountryText ?? "").isEmpty ||
            !(geolocationInlandWaterText ?? "").isEmpty ||
            !(geolocationOceanText ?? "").isEmpty ||
            !areas.isEmpty ||
            geolocationLatitudeText != nil ||
            geolocationLongitudeText != nil ||
            geolocationRadiusText != nil ||
            geolocationHorizontalAccuracyText != nil ||
            geolocationVerticalAccuracyText != nil ||
            geolocationAltitudeText != nil ||
            geolocationTimestampText != nil ||
            geolocationMinLatitudeText != nil ||
            geolocationMaxLatitudeText != nil ||
            geolocationMinLongitudeText != nil ||
            geolocationMaxLongitudeText != nil

        guard hasMeaningfulMetadata else { return nil }

        let latitude = parseDouble(geolocationLatitudeText, defaultValue: event.latitude)
        let longitude = parseDouble(geolocationLongitudeText, defaultValue: event.longitude)
        let radius = parseDouble(geolocationRadiusText, defaultValue: max(event.horizontalAccuracy, 0))
        let geolocationTimestamp = parseDate(geolocationTimestampText)

        return Geolocation(
            latitude: latitude,
            longitude: longitude,
            radius: radius,
            identifier: geolocationIdentifierText ?? "\(event.timestamp.timeIntervalSinceReferenceDate)-\(event.latitude)-\(event.longitude)",
            horizontalAccuracy: parseDouble(geolocationHorizontalAccuracyText, defaultValue: event.horizontalAccuracy),
            verticalAccuracy: parseDouble(geolocationVerticalAccuracyText, defaultValue: event.verticalAccuracy),
            altitude: parseDouble(geolocationAltitudeText, defaultValue: event.altitude),
            timestamp: geolocationTimestamp ?? event.timestamp,
            minLatitude: parseOptionalDouble(geolocationMinLatitudeText),
            maxLatitude: parseOptionalDouble(geolocationMaxLatitudeText),
            minLongitude: parseOptionalDouble(geolocationMinLongitudeText),
            maxLongitude: parseOptionalDouble(geolocationMaxLongitudeText),
            timeZoneIdentifier: timeZoneIdentifier ?? "",
            name: geolocationNameText ?? placeNameText ?? "",
            subThoroughfare: geolocationSubThoroughfareText ?? "",
            thoroughfare: geolocationThoroughfareText ?? "",
            subLocality: geolocationSubLocalityText ?? "",
            locality: geolocationLocalityText ?? "",
            subAdministrativeArea: geolocationSubAdministrativeAreaText ?? "",
            administrativeArea: geolocationAdministrativeAreaText ?? "",
            postalCode: geolocationPostalCodeText ?? "",
            isoCountryCode: geolocationIsoCountryCodeText ?? "",
            country: geolocationCountryText ?? "",
            inlandWater: geolocationInlandWaterText ?? "",
            ocean: geolocationOceanText ?? "",
            areasOfInterest: areas
        )
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let value, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func parseDouble(_ value: String?, defaultValue: Double = -1) -> Double {
        guard let value, let parsed = Double(value) else { return defaultValue }
        return parsed
    }

    private func parseOptionalDouble(_ value: String?) -> Double? {
        guard let value, let parsed = Double(value) else { return nil }
        return parsed
    }

    private func parseBool(_ value: String?) -> Bool {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return false }
        return ["1", "true", "yes", "y"].contains(value)
    }

    private func parseSolarPeriod(_ value: String?) -> SolarPeriod {
        guard let value, !value.isEmpty else { return .unknown }
        if let solarPeriod = SolarPeriod(rawValue: value) {
            return solarPeriod
        }
        if let twilightPhase = TwilightPhase(rawValue: value) {
            return SolarPeriod(twilightPhase: twilightPhase)
        }
        return .unknown
    }

    private func parseDate(_ value: String?, formatter: ISO8601DateFormatter? = nil) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        if let formatter, let date = formatter.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }

    private func parseTimestamp(_ value: String, formatter: ISO8601DateFormatter) -> Date? {
        if let date = formatter.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func localName(from rawName: String) -> String {
        rawName.split(separator: ":").last.map(String.init) ?? rawName
    }
}
