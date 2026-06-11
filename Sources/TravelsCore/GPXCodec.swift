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
    fileprivate static let travelsNamespace = "https://github.com/dkrnet/travels-ios/gpx/extensions/1"

    private static func timestampString(for date: Date, formatter: ISO8601DateFormatter, fractionalFormatter: ISO8601DateFormatter) -> String {
        let interval = date.timeIntervalSinceReferenceDate
        if interval.rounded(.towardZero) == interval {
            return formatter.string(from: date)
        }
        return fractionalFormatter.string(from: date)
    }

    public static func export(events: [EventDetail], title: String = "Travels life tracker log") throws -> String {
        guard !events.isEmpty else { throw TravelsError.emptyExport }
        let bounds = coordinateBounds(for: events)
        let formatter = TravelsDateTools.gpxFormatter()
        let fractionalFormatter = TravelsDateTools.gpxFractionalSecondsFormatter()
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Travels - life tracking" xmlns="http://www.topografix.com/GPX/1/1" xmlns:travels="\(travelsNamespace)" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
          <metadata>
            <name>\(escape(title))</name>
            <time>\(timestampString(for: Date(), formatter: formatter, fractionalFormatter: fractionalFormatter))</time>
            <bounds minlat="\(bounds.minLat)" maxlat="\(bounds.maxLat)" minlon="\(bounds.minLon)" maxlon="\(bounds.maxLon)"/>
          </metadata>
          <trk>
            <name>\(escape(title))</name>
            <trkseg>
        """

        for detail in events {
            appendTrackPoint(detail, formatter: formatter, fractionalFormatter: fractionalFormatter, to: &xml)
        }

        xml += """

            </trkseg>
          </trk>
        </gpx>
        """
        return xml
    }

    private static func appendTrackPoint(_ detail: EventDetail, formatter: ISO8601DateFormatter, fractionalFormatter: ISO8601DateFormatter, to xml: inout String) {
        let event = detail.event
        let geolocation = detail.geolocation

        xml += "\n      <trkpt lat=\"\(event.latitude)\" lon=\"\(event.longitude)\">"
        if event.altitude != 0 || event.verticalAccuracy >= 0 {
            xml += "\n        <ele>\(event.altitude)</ele>"
        }
        xml += "\n        <time>\(timestampString(for: event.timestamp, formatter: formatter, fractionalFormatter: fractionalFormatter))</time>"
        appendStandardText("name", geolocation?.name, to: &xml)
        appendStandardText("cmt", event.note, to: &xml)
        appendStandardText("desc", readablePlaceSummary(for: geolocation), to: &xml)
        appendStandardText("src", event.source.displayName, to: &xml)

        let eventExtension = eventExtensionXML(event: event, geolocation: geolocation, formatter: formatter, fractionalFormatter: fractionalFormatter)
        let placeExtension = geolocation.map { placeExtensionXML($0, formatter: formatter, fractionalFormatter: fractionalFormatter) } ?? ""

        if !eventExtension.isEmpty || !placeExtension.isEmpty {
            xml += "\n        <extensions>"
            if !eventExtension.isEmpty {
                xml += eventExtension
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

    private static func eventExtensionXML(event: LocationEvent, geolocation: Geolocation?, formatter: ISO8601DateFormatter, fractionalFormatter: ISO8601DateFormatter) -> String {
        var xml = ""
        appendTravelsText("horizontalAccuracyMeters", value: event.horizontalAccuracy >= 0 ? String(event.horizontalAccuracy) : nil, to: &xml)
        appendTravelsText("verticalAccuracyMeters", value: event.verticalAccuracy >= 0 ? String(event.verticalAccuracy) : nil, to: &xml)
        appendTravelsText("headingDegrees", value: event.course >= 0 ? String(event.course) : nil, to: &xml)
        appendTravelsText("speedMetersPerSecond", value: event.speed >= 0 ? String(event.speed) : nil, to: &xml)
        appendTravelsText("timeZone", value: geolocation?.timeZoneIdentifier, to: &xml)
        appendTravelsText("localizedDateKey", value: event.localizedDate, to: &xml)
        appendTravelsText("source", value: event.source.displayName, to: &xml)

        if !event.tags.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let tags = tagTokens(from: event.tags)
            xml += "\n          <travels:tags>"
            for tag in tags {
                xml += "\n            <travels:tag>\(escape(tag))</travels:tag>"
            }
            xml += "\n          </travels:tags>"
        }

        appendTravelsText("externalReference", value: event.externalReference, to: &xml)
        appendTravelsText("photoFilename", value: event.photoFilename, to: &xml)
        appendTravelsText("demoData", value: event.isDemo ? "true" : nil, to: &xml)

        if event.solarPeriod != .unknown || event.solarPeriodPercent != nil || event.solarPeriodCalculatedAt != nil {
            xml += "\n          <travels:solar>"
            appendTravelsText("period", value: event.solarPeriod.rawValue, to: &xml, indent: "            ")
            appendTravelsText("periodPercent", value: event.solarPeriodPercent.map { String($0) }, to: &xml, indent: "            ")
            appendTravelsText("calculatedAt", value: event.solarPeriodCalculatedAt.map { timestampString(for: $0, formatter: formatter, fractionalFormatter: fractionalFormatter) }, to: &xml, indent: "            ")
            xml += "\n          </travels:solar>"
        }

        return xml
    }

    private static func placeExtensionXML(_ geolocation: Geolocation, formatter: ISO8601DateFormatter, fractionalFormatter: ISO8601DateFormatter) -> String {
        var xml = ""
        appendTravelsText("identifier", value: geolocation.identifier, to: &xml)
        appendTravelsText("latitude", value: String(geolocation.latitude), to: &xml)
        appendTravelsText("longitude", value: String(geolocation.longitude), to: &xml)
        appendTravelsText("radiusMeters", value: String(geolocation.radius), to: &xml)
        appendTravelsText("horizontalAccuracyMeters", value: geolocation.horizontalAccuracy >= 0 ? String(geolocation.horizontalAccuracy) : nil, to: &xml)
        appendTravelsText("verticalAccuracyMeters", value: geolocation.verticalAccuracy >= 0 ? String(geolocation.verticalAccuracy) : nil, to: &xml)
        appendTravelsText("altitudeMeters", value: String(geolocation.altitude), to: &xml)
        appendTravelsText("timestamp", value: geolocation.timestamp.map { timestampString(for: $0, formatter: formatter, fractionalFormatter: fractionalFormatter) }, to: &xml)

        if geolocation.minLatitude != nil || geolocation.maxLatitude != nil || geolocation.minLongitude != nil || geolocation.maxLongitude != nil {
            xml += "\n          <travels:bounds>"
            appendTravelsText("minLatitude", value: geolocation.minLatitude.map { String($0) }, to: &xml, indent: "            ")
            appendTravelsText("maxLatitude", value: geolocation.maxLatitude.map { String($0) }, to: &xml, indent: "            ")
            appendTravelsText("minLongitude", value: geolocation.minLongitude.map { String($0) }, to: &xml, indent: "            ")
            appendTravelsText("maxLongitude", value: geolocation.maxLongitude.map { String($0) }, to: &xml, indent: "            ")
            xml += "\n          </travels:bounds>"
        }

        appendTravelsText("name", value: geolocation.name, to: &xml)
        appendTravelsText("subThoroughfare", value: geolocation.subThoroughfare, to: &xml)
        appendTravelsText("thoroughfare", value: geolocation.thoroughfare, to: &xml)
        appendTravelsText("subLocality", value: geolocation.subLocality, to: &xml)
        appendTravelsText("locality", value: geolocation.locality, to: &xml)
        appendTravelsText("subAdministrativeArea", value: geolocation.subAdministrativeArea, to: &xml)
        appendTravelsText("administrativeArea", value: geolocation.administrativeArea, to: &xml)
        appendTravelsText("postalCode", value: geolocation.postalCode, to: &xml)
        appendTravelsText("isoCountryCode", value: geolocation.isoCountryCode, to: &xml)
        appendTravelsText("country", value: geolocation.country, to: &xml)
        appendTravelsText("inlandWater", value: geolocation.inlandWater, to: &xml)
        appendTravelsText("ocean", value: geolocation.ocean, to: &xml)

        if !geolocation.areasOfInterest.isEmpty {
            xml += "\n          <travels:areasOfInterest>"
            for area in geolocation.areasOfInterest {
                xml += "\n            <travels:areaOfInterest>\(escape(area))</travels:areaOfInterest>"
            }
            xml += "\n          </travels:areasOfInterest>"
        }

        return xml
    }

    private static func tagTokens(from tags: String) -> [String] {
        tags
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func readablePlaceSummary(for geolocation: Geolocation?) -> String? {
        guard let geolocation else { return nil }
        let parts = [
            geolocation.name,
            geolocation.locality,
            geolocation.administrativeArea,
            geolocation.country
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        return parts.isEmpty ? nil : parts.joined(separator: ", ")
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

private struct GPXElementContext {
    let localName: String
    let isTravelsNamespace: Bool
}

private final class GPXTrackParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var elementStack: [GPXElementContext] = []
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
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
    }

    func parse() throws -> GPXImportResult {
        guard parser.parse() else {
            throw TravelsError.invalidGPX(parser.parserError?.localizedDescription ?? "Unable to parse GPX")
        }
        return GPXImportResult(events: trackPoints.map(\.event), trackPoints: trackPoints, skippedInvalidPoints: skipped)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let localName = normalizedElementName(elementName, qualifiedName: qName)
        let isTravelsNamespace = (namespaceURI == GPXExporter.travelsNamespace) || (qName?.hasPrefix("travels:") == true)
        elementStack.append(GPXElementContext(localName: localName, isTravelsNamespace: isTravelsNamespace))
        textStack.append("")

        if localName == "trkpt" {
            currentPoint = GPXTrackPointBuilder(attributes: attributeDict)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !textStack.isEmpty else { return }
        textStack[textStack.count - 1] += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let localName = normalizedElementName(elementName, qualifiedName: qName)
        let text = textStack.popLast()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        defer {
            _ = elementStack.popLast()
        }

        if let currentPoint, !text.isEmpty {
            currentPoint.consume(text: text, path: elementStack)
        }

        if localName == "trkpt" {
            if let trackPoint = currentPoint?.build(using: formatter) {
                trackPoints.append(trackPoint)
            } else {
                skipped += 1
            }
            currentPoint = nil
        }
    }

    private func normalizedElementName(_ elementName: String, qualifiedName: String?) -> String {
        (qualifiedName ?? elementName).split(separator: ":").last.map(String.init) ?? elementName
    }
}

private final class GPXTrackPointBuilder {
    private let attributes: [String: String]

    private var timestampText: String?
    private var altitudeText: String?
    private var noteText: String?
    private var standardNameText: String?
    private var standardSourceText: String?
    private var eventSourceText: String?
    private var eventHorizontalAccuracyText: String?
    private var eventVerticalAccuracyText: String?
    private var eventHeadingText: String?
    private var eventSpeedText: String?
    private var eventTimeZoneText: String?
    private var eventLocalizedDateText: String?
    private var eventExternalReferenceText: String?
    private var eventPhotoFilenameText: String?
    private var eventDemoDataText: String?
    private var eventSolarPeriodText: String?
    private var eventSolarPeriodPercentText: String?
    private var eventSolarCalculatedAtText: String?

    private var placeIdentifierText: String?
    private var placeLatitudeText: String?
    private var placeLongitudeText: String?
    private var placeRadiusText: String?
    private var placeHorizontalAccuracyText: String?
    private var placeVerticalAccuracyText: String?
    private var placeAltitudeText: String?
    private var placeTimestampText: String?
    private var placeMinLatitudeText: String?
    private var placeMaxLatitudeText: String?
    private var placeMinLongitudeText: String?
    private var placeMaxLongitudeText: String?
    private var placeTimeZoneText: String?
    private var placeNameText: String?
    private var placeSubThoroughfareText: String?
    private var placeThoroughfareText: String?
    private var placeSubLocalityText: String?
    private var placeLocalityText: String?
    private var placeSubAdministrativeAreaText: String?
    private var placeAdministrativeAreaText: String?
    private var placePostalCodeText: String?
    private var placeIsoCountryCodeText: String?
    private var placeCountryText: String?
    private var placeInlandWaterText: String?
    private var placeOceanText: String?
    private var placeSummaryText: String?
    private var placeLegacyAreasOfInterestText: String?
    private var placeCanonicalAreasOfInterest: [String] = []

    private var legacyTagsText: String?
    private var canonicalTags: [String] = []

    init(attributes: [String: String]) {
        self.attributes = attributes
    }

    func consume(text: String, path: [GPXElementContext]) {
        let names = path.map(\.localName)
        let last = names.last ?? ""
        let isNamespaced = path.last?.isTravelsNamespace == true
        let containsPlace = names.contains("place")
        let containsSolar = names.contains("solar")
        let containsBounds = names.contains("bounds")

        switch last {
        case "time":
            timestampText = text
        case "ele":
            altitudeText = text
        case "name" where containsPlace:
            store(text, in: &placeNameText, namespaced: isNamespaced)
        case "name":
            store(text, in: &standardNameText, namespaced: isNamespaced)
        case "desc":
            placeSummaryText = text
        case "cmt", "note":
            store(text, in: &noteText, namespaced: isNamespaced)
        case "src":
            store(text, in: &standardSourceText, namespaced: isNamespaced)
        case "source":
            store(text, in: &eventSourceText, namespaced: isNamespaced)
        case "heading", "course":
            store(text, in: &eventHeadingText, namespaced: isNamespaced)
        case "speed":
            store(text, in: &eventSpeedText, namespaced: isNamespaced)
        case "horizontalAccuracyMeters":
            if containsPlace {
                store(text, in: &placeHorizontalAccuracyText, namespaced: isNamespaced)
            } else {
                store(text, in: &eventHorizontalAccuracyText, namespaced: isNamespaced)
            }
        case "horizontalAccuracy":
            if containsPlace {
                store(text, in: &placeHorizontalAccuracyText, namespaced: isNamespaced)
            } else {
                store(text, in: &eventHorizontalAccuracyText, namespaced: isNamespaced)
            }
        case "verticalAccuracyMeters":
            if containsPlace {
                store(text, in: &placeVerticalAccuracyText, namespaced: isNamespaced)
            } else {
                store(text, in: &eventVerticalAccuracyText, namespaced: isNamespaced)
            }
        case "verticalAccuracy":
            if containsPlace {
                store(text, in: &placeVerticalAccuracyText, namespaced: isNamespaced)
            } else {
                store(text, in: &eventVerticalAccuracyText, namespaced: isNamespaced)
            }
        case "timeZone":
            if containsPlace {
                store(text, in: &placeTimeZoneText, namespaced: isNamespaced)
            } else {
                store(text, in: &eventTimeZoneText, namespaced: isNamespaced)
            }
        case "timeZoneIdentifier":
            if containsPlace {
                store(text, in: &placeTimeZoneText, namespaced: isNamespaced)
            } else {
                store(text, in: &eventTimeZoneText, namespaced: isNamespaced)
            }
        case "localizedDateKey":
            store(text, in: &eventLocalizedDateText, namespaced: isNamespaced)
        case "localizedDate":
            store(text, in: &eventLocalizedDateText, namespaced: isNamespaced)
        case "tags":
            if isNamespaced {
                // Wrapper element; child <travels:tag> values are captured separately.
            } else {
                // REGRESSION GUARD: legacy flat <tags> values remain accepted as a fallback alias.
                legacyTagsText = text
            }
        case "tag":
            if isNamespaced {
                canonicalTags.append(text)
            } else if legacyTagsText == nil {
                legacyTagsText = text
            } else {
                legacyTagsText = (legacyTagsText ?? "") + "\n" + text
            }
        case "externalReference":
            store(text, in: &eventExternalReferenceText, namespaced: isNamespaced)
        case "photoFilename":
            store(text, in: &eventPhotoFilenameText, namespaced: isNamespaced)
        case "demoData", "isDemo":
            store(text, in: &eventDemoDataText, namespaced: isNamespaced)
        case "period":
            if containsSolar {
                store(text, in: &eventSolarPeriodText, namespaced: isNamespaced)
            }
        case "solarPeriod":
            store(text, in: &eventSolarPeriodText, namespaced: isNamespaced)
        case "periodPercent":
            if containsSolar {
                store(text, in: &eventSolarPeriodPercentText, namespaced: isNamespaced)
            }
        case "solarPeriodPercent":
            store(text, in: &eventSolarPeriodPercentText, namespaced: isNamespaced)
        case "calculatedAt":
            if containsSolar {
                store(text, in: &eventSolarCalculatedAtText, namespaced: isNamespaced)
            }
        case "solarPeriodCalculatedAt":
            store(text, in: &eventSolarCalculatedAtText, namespaced: isNamespaced)
        case "identifier":
            if containsPlace {
                store(text, in: &placeIdentifierText, namespaced: isNamespaced)
            }
        case "latitude":
            if containsPlace {
                store(text, in: &placeLatitudeText, namespaced: isNamespaced)
            }
        case "longitude":
            if containsPlace {
                store(text, in: &placeLongitudeText, namespaced: isNamespaced)
            }
        case "radiusMeters", "radius":
            if containsPlace {
                store(text, in: &placeRadiusText, namespaced: isNamespaced)
            }
        case "altitudeMeters":
            if containsPlace {
                store(text, in: &placeAltitudeText, namespaced: isNamespaced)
            }
        case "timestamp":
            if containsPlace {
                store(text, in: &placeTimestampText, namespaced: isNamespaced)
            }
        case "minLatitude":
            if containsBounds || containsPlace {
                store(text, in: &placeMinLatitudeText, namespaced: isNamespaced)
            }
        case "maxLatitude":
            if containsBounds || containsPlace {
                store(text, in: &placeMaxLatitudeText, namespaced: isNamespaced)
            }
        case "minLongitude":
            if containsBounds || containsPlace {
                store(text, in: &placeMinLongitudeText, namespaced: isNamespaced)
            }
        case "maxLongitude":
            if containsBounds || containsPlace {
                store(text, in: &placeMaxLongitudeText, namespaced: isNamespaced)
            }
        case "subThoroughfare":
            if containsPlace || !isNamespaced {
                store(text, in: &placeSubThoroughfareText, namespaced: isNamespaced)
            }
        case "thoroughfare":
            if containsPlace || !isNamespaced {
                store(text, in: &placeThoroughfareText, namespaced: isNamespaced)
            }
        case "subLocality":
            if containsPlace || !isNamespaced {
                store(text, in: &placeSubLocalityText, namespaced: isNamespaced)
            }
        case "locality":
            if containsPlace || !isNamespaced {
                store(text, in: &placeLocalityText, namespaced: isNamespaced)
            }
        case "subAdministrativeArea":
            if containsPlace || !isNamespaced {
                store(text, in: &placeSubAdministrativeAreaText, namespaced: isNamespaced)
            }
        case "administrativeArea":
            if containsPlace || !isNamespaced {
                store(text, in: &placeAdministrativeAreaText, namespaced: isNamespaced)
            }
        case "postalCode":
            if containsPlace || !isNamespaced {
                store(text, in: &placePostalCodeText, namespaced: isNamespaced)
            }
        case "isoCountryCode":
            if containsPlace || !isNamespaced {
                store(text, in: &placeIsoCountryCodeText, namespaced: isNamespaced)
            }
        case "country":
            // BUGFIX: legacy Travels GPX trackpoints store place metadata as flat children, so keep accepting country even when it is not wrapped in the newer namespaced <place> block.
            if containsPlace || !isNamespaced {
                store(text, in: &placeCountryText, namespaced: isNamespaced)
            }
        case "inlandWater":
            if containsPlace || !isNamespaced {
                store(text, in: &placeInlandWaterText, namespaced: isNamespaced)
            }
        case "ocean":
            if containsPlace || !isNamespaced {
                store(text, in: &placeOceanText, namespaced: isNamespaced)
            }
        case "areaOfInterest":
            if isNamespaced {
                placeCanonicalAreasOfInterest.append(text)
            } else if placeLegacyAreasOfInterestText == nil {
                placeLegacyAreasOfInterestText = text
            } else {
                placeLegacyAreasOfInterestText = (placeLegacyAreasOfInterestText ?? "") + "|||TRAVELS|||" + text
            }
        case "areasOfInterest":
            if !isNamespaced {
                placeLegacyAreasOfInterestText = text
            }
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

        let eventTimeZoneIdentifier = firstNonEmpty(eventTimeZoneText, placeTimeZoneText)
        let localizedDate = firstNonEmpty(eventLocalizedDateText, eventTimeZoneIdentifier.map { TravelsDateTools.localizedDayString(for: timestamp, timeZoneIdentifier: $0) })
        let eventTags = canonicalTags.isEmpty ? legacyTagsText ?? "" : canonicalTags.joined(separator: "\n")
        let solarPeriod = parseSolarPeriod(eventSolarPeriodText)
        let source = parseEventSource(firstNonEmpty(eventSourceText, standardSourceText))
        let solarCalculatedAt = parseDate(eventSolarCalculatedAtText, formatter: formatter)

        let event = LocationEvent(
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracy: parseDouble(firstNonEmpty(eventHorizontalAccuracyText, placeHorizontalAccuracyText)),
            verticalAccuracy: parseDouble(firstNonEmpty(eventVerticalAccuracyText, placeVerticalAccuracyText)),
            altitude: parseDouble(firstNonEmpty(altitudeText, placeAltitudeText), defaultValue: 0),
            course: parseDouble(firstNonEmpty(eventHeadingText)),
            speed: parseDouble(firstNonEmpty(eventSpeedText)),
            timestamp: timestamp,
            localizedDate: localizedDate,
            source: source,
            note: noteText ?? "",
            tags: eventTags,
            externalReference: eventExternalReferenceText ?? "",
            photoFilename: eventPhotoFilenameText ?? "",
            isDemo: parseBool(eventDemoDataText),
            solarPeriod: solarPeriod,
            solarPeriodPercent: parseDouble(eventSolarPeriodPercentText),
            solarPeriodCalculatedAt: solarCalculatedAt
        )

        return GPXTrackPoint(event: event, geolocation: geolocation(for: event, timeZoneIdentifier: eventTimeZoneIdentifier))
    }

    private func geolocation(for event: LocationEvent, timeZoneIdentifier: String?) -> Geolocation? {
        let areas = placeCanonicalAreasOfInterest.isEmpty
            ? Geolocation.normalizedAreasOfInterest(placeLegacyAreasOfInterestText?.components(separatedBy: "|||TRAVELS|||") ?? [])
            : Geolocation.normalizedAreasOfInterest(placeCanonicalAreasOfInterest)

        let hasMeaningfulMetadata =
            !(placeIdentifierText ?? "").isEmpty ||
            !(timeZoneIdentifier ?? "").isEmpty ||
            !(placeNameText ?? "").isEmpty ||
            !(standardNameText ?? "").isEmpty ||
            !(placeSummaryText ?? "").isEmpty ||
            !(placeSubThoroughfareText ?? "").isEmpty ||
            !(placeThoroughfareText ?? "").isEmpty ||
            !(placeSubLocalityText ?? "").isEmpty ||
            !(placeLocalityText ?? "").isEmpty ||
            !(placeSubAdministrativeAreaText ?? "").isEmpty ||
            !(placeAdministrativeAreaText ?? "").isEmpty ||
            !(placePostalCodeText ?? "").isEmpty ||
            !(placeIsoCountryCodeText ?? "").isEmpty ||
            !(placeCountryText ?? "").isEmpty ||
            !(placeInlandWaterText ?? "").isEmpty ||
            !(placeOceanText ?? "").isEmpty ||
            !areas.isEmpty ||
            placeLatitudeText != nil ||
            placeLongitudeText != nil ||
            placeRadiusText != nil ||
            placeHorizontalAccuracyText != nil ||
            placeVerticalAccuracyText != nil ||
            placeAltitudeText != nil ||
            placeTimestampText != nil ||
            placeMinLatitudeText != nil ||
            placeMaxLatitudeText != nil ||
            placeMinLongitudeText != nil ||
            placeMaxLongitudeText != nil

        guard hasMeaningfulMetadata else { return nil }

        let latitude = parseDouble(placeLatitudeText, defaultValue: event.latitude)
        let longitude = parseDouble(placeLongitudeText, defaultValue: event.longitude)
        let radius = parseDouble(placeRadiusText, defaultValue: max(event.horizontalAccuracy, 0))
        let geolocationTimestamp = parseDate(placeTimestampText)

        return Geolocation(
            latitude: latitude,
            longitude: longitude,
            radius: radius,
            identifier: placeIdentifierText ?? "\(event.timestamp.timeIntervalSinceReferenceDate)-\(event.latitude)-\(event.longitude)",
            horizontalAccuracy: parseDouble(placeHorizontalAccuracyText, defaultValue: event.horizontalAccuracy),
            verticalAccuracy: parseDouble(placeVerticalAccuracyText, defaultValue: event.verticalAccuracy),
            altitude: parseDouble(placeAltitudeText, defaultValue: event.altitude),
            timestamp: geolocationTimestamp ?? event.timestamp,
            minLatitude: parseOptionalDouble(placeMinLatitudeText),
            maxLatitude: parseOptionalDouble(placeMaxLatitudeText),
            minLongitude: parseOptionalDouble(placeMinLongitudeText),
            maxLongitude: parseOptionalDouble(placeMaxLongitudeText),
            timeZoneIdentifier: timeZoneIdentifier ?? "",
            name: firstNonEmpty(placeNameText, standardNameText, placeSummaryText) ?? "",
            subThoroughfare: placeSubThoroughfareText ?? "",
            thoroughfare: placeThoroughfareText ?? "",
            subLocality: placeSubLocalityText ?? "",
            locality: placeLocalityText ?? "",
            subAdministrativeArea: placeSubAdministrativeAreaText ?? "",
            administrativeArea: placeAdministrativeAreaText ?? "",
            postalCode: placePostalCodeText ?? "",
            isoCountryCode: placeIsoCountryCodeText ?? "",
            country: placeCountryText ?? "",
            inlandWater: placeInlandWaterText ?? "",
            ocean: placeOceanText ?? "",
            areasOfInterest: areas
        )
    }

    private func store(_ text: String, in value: inout String?, namespaced: Bool) {
        // BUGFIX: canonical Travels v1 values must win over legacy aliases when both are present.
        if namespaced || value == nil {
            value = text
        }
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

    private func parseEventSource(_ value: String?) -> EventSource {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return .imported
        }

        if let source = EventSource(rawValue: Int(value) ?? -1) {
            return source
        }

        switch value.lowercased() {
        case EventSource.locationServices.displayName.lowercased():
            return .locationServices
        case EventSource.imported.displayName.lowercased():
            return .imported
        case EventSource.photo.displayName.lowercased():
            return .photo
        case EventSource.manual.displayName.lowercased():
            return .manual
        case EventSource.invalid.displayName.lowercased():
            return .invalid
        case EventSource.simulated.displayName.lowercased():
            return .simulated
        default:
            return .imported
        }
    }

    private let fractionalFormatter = TravelsDateTools.gpxFractionalSecondsFormatter()

    private func parseDate(_ value: String?, formatter: ISO8601DateFormatter? = nil) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        if let formatter, let date = formatter.date(from: value) {
            return date
        }
        if let date = fractionalFormatter.date(from: value) {
            return date
        }
        if let interval = Double(value) {
            return Date(timeIntervalSinceReferenceDate: interval)
        }
        return ISO8601DateFormatter().date(from: value)
    }

    private func parseTimestamp(_ value: String, formatter: ISO8601DateFormatter) -> Date? {
        if let date = formatter.date(from: value) {
            return date
        }
        if let date = fractionalFormatter.date(from: value) {
            return date
        }
        if let interval = Double(value) {
            return Date(timeIntervalSinceReferenceDate: interval)
        }
        return ISO8601DateFormatter().date(from: value)
    }

}
