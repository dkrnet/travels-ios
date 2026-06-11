// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public func isMovingLocationEvent(_ event: LocationEvent) -> Bool {
    event.speed > 0
}

public func isStoppedLocationEvent(_ event: LocationEvent) -> Bool {
    !isMovingLocationEvent(event)
}

public func tripDetectionEvents(
    from events: [EventDetail],
    displayedDate: Date
) -> [LocationEvent] {
    let displayedDay = TravelsDateTools.localizedDayString(
        for: displayedDate,
        timeZoneIdentifier: nil
    )
    return events.compactMap { detail in
        guard detail.event.localizedDate == displayedDay else { return nil }
        return detail.event
    }
}

public struct DetectedTrip: Identifiable, Equatable, Sendable {
    public let id: String
    public let movingStartDate: Date
    public let movingEndDate: Date
    public let movingEventIDs: Set<LocationEvent.ID>
    public let endpointEventIDs: Set<LocationEvent.ID>
    public let displayEventIDs: Set<LocationEvent.ID>
    public let displayName: String

    public init(
        id: String,
        movingStartDate: Date,
        movingEndDate: Date,
        movingEventIDs: Set<LocationEvent.ID>,
        endpointEventIDs: Set<LocationEvent.ID>,
        displayEventIDs: Set<LocationEvent.ID>,
        displayName: String
    ) {
        self.id = id
        self.movingStartDate = movingStartDate
        self.movingEndDate = movingEndDate
        self.movingEventIDs = movingEventIDs
        self.endpointEventIDs = endpointEventIDs
        self.displayEventIDs = displayEventIDs
        self.displayName = displayName
    }
}

public enum MapDisplaySelection: Equatable, Sendable {
    case all
    case stoppedOnly
    case trips(Set<DetectedTrip.ID>)
}

public struct TripDetectionService: Sendable {
    public static let tripSeparationInterval: TimeInterval = 30 * 60

    public init() {}

    public func detectTrips(
        from events: [LocationEvent],
        timeZone: TimeZone,
        tripSeparationInterval: TimeInterval = Self.tripSeparationInterval
    ) -> [DetectedTrip] {
        let orderedEvents = Self.sortedEvents(events)
        guard !orderedEvents.isEmpty else { return [] }

        var partialTrips: [PartialTrip] = []
        var currentTrip: PartialTrip?
        var pendingStartingEndpoint: LocationEvent?

        for event in orderedEvents {
            if isMovingLocationEvent(event) {
                if var activeTrip = currentTrip {
                    if let lastMovingEvent = activeTrip.lastMovingEvent,
                       event.timestamp.timeIntervalSince(lastMovingEvent.timestamp) >= tripSeparationInterval {
                        partialTrips.append(activeTrip)
                        var newTrip = PartialTrip(startingEndpoint: pendingStartingEndpoint)
                        newTrip.addMoving(event)
                        currentTrip = newTrip
                        pendingStartingEndpoint = nil
                        continue
                    }

                    activeTrip.addMoving(event)
                    currentTrip = activeTrip
                    continue
                }

                var newTrip = PartialTrip(startingEndpoint: pendingStartingEndpoint)
                newTrip.addMoving(event)
                currentTrip = newTrip
                pendingStartingEndpoint = nil
                continue
            }

            if var activeTrip = currentTrip {
                activeTrip.addEndingEndpoint(event)
                partialTrips.append(activeTrip)
                currentTrip = nil
                pendingStartingEndpoint = event
            } else {
                pendingStartingEndpoint = event
            }
        }

        if let currentTrip {
            partialTrips.append(currentTrip)
        }

        let completedTrips = partialTrips.compactMap { $0.makeTrip(timeZone: timeZone) }
        return Self.numberedTrips(completedTrips.sorted { $0.movingStartDate < $1.movingStartDate })
    }

    private static func numberedTrips(_ trips: [DetectedTrip]) -> [DetectedTrip] {
        let baseNames = trips.map(\.displayName)
        var counts: [String: Int] = [:]
        for name in baseNames {
            counts[name, default: 0] += 1
        }

        var occurrences: [String: Int] = [:]
        return trips.enumerated().map { index, trip in
            let baseName = baseNames[index]
            guard (counts[baseName] ?? 0) > 1 else {
                return trip
            }
            occurrences[baseName, default: 0] += 1
            return trip.replacingDisplayName("\(baseName) \(occurrences[baseName]!)")
        }
    }

    private static func sortedEvents(_ events: [LocationEvent]) -> [LocationEvent] {
        events.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }

            let lhsID = lhs.id ?? .max
            let rhsID = rhs.id ?? .max
            if lhsID != rhsID {
                return lhsID < rhsID
            }

            if lhs.source.rawValue != rhs.source.rawValue {
                return lhs.source.rawValue < rhs.source.rawValue
            }

            if lhs.latitude != rhs.latitude {
                return lhs.latitude < rhs.latitude
            }

            if lhs.longitude != rhs.longitude {
                return lhs.longitude < rhs.longitude
            }

            if lhs.speed != rhs.speed {
                return lhs.speed < rhs.speed
            }

            if lhs.course != rhs.course {
                return lhs.course < rhs.course
            }

            return lhs.horizontalAccuracy < rhs.horizontalAccuracy
        }
    }
}

public func filteredEvents(
    from events: [EventDetail],
    selection: MapDisplaySelection,
    detectedTrips: [DetectedTrip]
) -> [EventDetail] {
    switch selection {
    case .all:
        return events

    case .stoppedOnly:
        return events.filter { isStoppedLocationEvent($0.event) }

    case .trips(let tripIDs):
        guard !tripIDs.isEmpty else {
            return []
        }
        let allowedIDs = Set(
            detectedTrips
                .filter { tripIDs.contains($0.id) }
                .flatMap { $0.displayEventIDs.compactMap { $0 } }
        )
        guard !allowedIDs.isEmpty else { return [] }
        return events.filter { detail in
            guard let id = detail.id else { return false }
            return allowedIDs.contains(id)
        }
    }
}

private struct PartialTrip {
    var movingEvents: [LocationEvent] = []
    var startingEndpoint: LocationEvent?
    var endingEndpoint: LocationEvent?

    var lastMovingEvent: LocationEvent? {
        movingEvents.last
    }

    mutating func addMoving(_ event: LocationEvent) {
        movingEvents.append(event)
    }

    mutating func addEndingEndpoint(_ event: LocationEvent) {
        endingEndpoint = event
    }

    func makeTrip(timeZone: TimeZone) -> DetectedTrip? {
        guard let firstMoving = movingEvents.first, let lastMoving = movingEvents.last else {
            return nil
        }

        let movingEventIDs = Set(movingEvents.map(\.id))
        var endpointEventIDs = Set<LocationEvent.ID>()
        endpointEventIDs.insert(startingEndpoint?.id)
        endpointEventIDs.insert(endingEndpoint?.id)

        let displayEventIDs = movingEventIDs.union(endpointEventIDs)
        let rawName = Self.displayName(
            start: firstMoving.timestamp,
            end: lastMoving.timestamp,
            timeZone: timeZone
        )

        return DetectedTrip(
            id: Self.identifier(for: firstMoving, lastMoving: lastMoving),
            movingStartDate: firstMoving.timestamp,
            movingEndDate: lastMoving.timestamp,
            movingEventIDs: movingEventIDs,
            endpointEventIDs: endpointEventIDs,
            displayEventIDs: displayEventIDs,
            displayName: Self.displayNameForPresentation(rawName)
        )
    }

    private static func identifier(for firstMoving: LocationEvent, lastMoving: LocationEvent) -> String {
        "trip-\(identityString(for: firstMoving))-\(identityString(for: lastMoving))"
    }

    private static func identityString(for event: LocationEvent) -> String {
        if let id = event.id {
            return String(id)
        }
        return String(format: "t%.6f", event.timestamp.timeIntervalSinceReferenceDate)
    }

    private static func displayName(start: Date, end: Date, timeZone: TimeZone) -> String {
        let startLabel = dayPartLabel(for: start, timeZone: timeZone)
        let endLabel = dayPartLabel(for: end, timeZone: timeZone)
        if startLabel == endLabel {
            return startLabel
        }
        return "\(startLabel) to \(endLabel)"
    }

    private static func displayNameForPresentation(_ rawName: String) -> String {
        guard let first = rawName.first else { return rawName }
        return first.uppercased() + rawName.dropFirst()
    }

    private static func dayPartLabel(for date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)

        switch minutes {
        case 0..<240:
            return "midnight"
        case 240..<360:
            return "pre-dawn"
        case 360..<540:
            return "early morning"
        case 540..<660:
            return "morning"
        case 660..<720:
            return "late morning"
        case 720..<780:
            return "mid-day"
        case 780..<900:
            return "early afternoon"
        case 900..<1020:
            return "midafternoon"
        case 1020..<1140:
            return "late afternoon"
        case 1140..<1320:
            return "evening"
        default:
            return "night"
        }
    }
}

private extension DetectedTrip {
    func replacingDisplayName(_ displayName: String) -> DetectedTrip {
        DetectedTrip(
            id: id,
            movingStartDate: movingStartDate,
            movingEndDate: movingEndDate,
            movingEventIDs: movingEventIDs,
            endpointEventIDs: endpointEventIDs,
            displayEventIDs: displayEventIDs,
            displayName: displayName
        )
    }
}
