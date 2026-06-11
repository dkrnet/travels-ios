// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.

import MapKit
import SwiftUI
import UIKit

#if canImport(TravelsCore)
import TravelsCore
#endif

private let timeOfDayColorResolver = TimeOfDayColorResolver()

private extension Color {
    init(_ rgb: RGBColor) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

struct EventMapView: View {
    @EnvironmentObject private var model: TravelsModel
    let day: Date
    let events: [EventDetail]
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var mapViewportSize: CGSize = .zero
    private let minimumMarkerSpacing: CGFloat = 35

    var body: some View {
        GeometryReader { geometry in
            Map(position: $cameraPosition) {
                ForEach(routeSegments) { segment in
                    MapPolyline(coordinates: segment.coordinates)
                        .stroke(segment.color, lineWidth: 3)
                }
                ForEach(displayedEvents) { detail in
                    Annotation(markerTitle(for: detail), coordinate: detail.coordinate) {
                        Button {
                            model.selectedEvent = detail
                        } label: {
                            EventMapBadge(detail: detail)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .onAppear {
                mapViewportSize = geometry.size
                updateCameraPosition()
            }
            .onChange(of: geometry.size) { _, newSize in
                mapViewportSize = newSize
                updateCameraPosition()
            }
            .onChange(of: day) { _, _ in
                updateCameraPosition()
            }
            .onChange(of: model.mapCameraCommandID) { _, _ in
                updateCameraPosition()
            }
            .onChange(of: events.count) { _, newValue in
                updateCameraPosition()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                model.updateMapCameraRegion(context.region)
                updateVisibleEventIDs(in: context.region)
            }
        }
    }

    private var routeSegments: [RouteSegment] {
        let orderedEvents = events.sorted { $0.event.timestamp < $1.event.timestamp }
        guard orderedEvents.count > 1 else { return [] }
        return orderedEvents.indices.dropLast().map { index in
            RouteSegment(
                id: "\(index)-\(index + 1)",
                coordinates: [orderedEvents[index].coordinate, orderedEvents[index + 1].coordinate],
                color: color(for: orderedEvents[index + 1]).opacity(0.9)
            )
        }
    }

    private var displayedEvents: [EventDetail] {
        let visibleEvents = focusedEvents().isEmpty
            ? visibleEvents(in: model.mapCameraRegion)
            : focusedEvents()
        return Self.spacedEvents(
            from: visibleEvents,
            selectedEventID: model.selectedEvent?.id,
            region: model.mapCameraRegion,
            viewportSize: effectiveViewportSize,
            minimumSpacing: minimumMarkerSpacing,
            detectedTrips: model.detectedTrips
        )
    }

    private var effectiveViewportSize: CGSize {
        if mapViewportSize.width > 0 && mapViewportSize.height > 0 {
            return mapViewportSize
        }
        return UIScreen.main.bounds.size
    }

    private func markerTitle(for detail: EventDetail) -> String {
        guard shouldShowMarkerLabel(for: detail) else {
            return ""
        }
        return detail.geolocation?.name ?? ""
    }

    private func shouldShowMarkerLabel(for detail: EventDetail) -> Bool {
        guard isStoppedLocationEvent(detail.event) else { return false }
        guard let geolocation = detail.geolocation else { return false }
        let name = geolocation.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return false
        }
        return true
    }

    private func updateCameraPosition() {
        let focusEvents = focusedEvents()
        let visibleEvents = focusEvents.isEmpty
            ? fullDayEvents()
            : Self.spacedEvents(
                from: focusEvents,
                selectedEventID: model.selectedEvent?.id,
                region: model.mapCameraRegion,
                viewportSize: effectiveViewportSize,
                minimumSpacing: minimumMarkerSpacing,
                detectedTrips: model.detectedTrips
            )

        guard !visibleEvents.isEmpty else {
            cameraPosition = .automatic
            model.updateMapVisibleEventIDs([])
            return
        }

        let latitudes = visibleEvents.map(\.event.latitude)
        let longitudes = visibleEvents.map(\.event.longitude)
        let minLatitude = latitudes.min() ?? 0
        let maxLatitude = latitudes.max() ?? 0
        let minLongitude = longitudes.min() ?? 0
        let maxLongitude = longitudes.max() ?? 0

        if visibleEvents.count == 1 {
            let coordinate = visibleEvents[0].coordinate
            let region = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
            withAnimation(.easeInOut(duration: 0.25)) {
                cameraPosition = .region(region)
            }
            model.updateMapVisibleEventIDs(visibleEvents.compactMap(\.id))
            model.mapFocusEventIDs = nil
            return
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let latitudeDelta = max((maxLatitude - minLatitude) * 1.35, 0.01)
        let longitudeDelta = max((maxLongitude - minLongitude) * 1.35, 0.01)
        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
        withAnimation(.easeInOut(duration: 0.25)) {
            cameraPosition = .region(region)
        }
        model.updateMapVisibleEventIDs(visibleEvents.compactMap(\.id))
        model.mapFocusEventIDs = nil
    }

    private func fullDayEvents() -> [EventDetail] {
        let dayString = TravelsDateTools.localizedDayString(for: day, timeZoneIdentifier: nil)
        // BUGFIX: the zoom/reset controls must use the currently displayed subset, not the entire day's data.
        let dayEvents = events.filter { $0.event.localizedDate == dayString }
        return dayEvents.isEmpty ? events : dayEvents
    }

    private func focusedEvents() -> [EventDetail] {
        guard let focusIDs = model.mapFocusEventIDs, !focusIDs.isEmpty else { return [] }
        let focusSet = Set(focusIDs)
        return events.filter { detail in
            guard let id = detail.id else { return false }
            return focusSet.contains(id)
        }
    }

    private func updateVisibleEventIDs(in region: MKCoordinateRegion?) {
        guard let region else {
            model.updateMapVisibleEventIDs(displayedEvents.compactMap(\.id))
            return
        }

        let visibleIDs = displayedEvents.compactMap { detail -> Int64? in
            guard let id = detail.id else { return nil }
            guard isCoordinate(detail.coordinate, inside: region) else { return nil }
            return id
        }
        model.updateMapVisibleEventIDs(visibleIDs)
    }

    private func visibleEvents(in region: MKCoordinateRegion?) -> [EventDetail] {
        guard let region else { return events }
        return events.filter { detail in
            isCoordinate(detail.coordinate, inside: region)
        }
    }

    private static func spacedEvents(
        from events: [EventDetail],
        selectedEventID: Int64?,
        region: MKCoordinateRegion?,
        viewportSize: CGSize,
        minimumSpacing: CGFloat,
        detectedTrips: [DetectedTrip]
    ) -> [EventDetail] {
        let ordered = events.sorted { $0.event.timestamp < $1.event.timestamp }
        guard ordered.count > 1 else { return ordered }

        let baseline = spacedEvents(
            within: ordered,
            selectedEventID: selectedEventID,
            region: region,
            viewportSize: viewportSize,
            minimumSpacing: minimumSpacing
        )

        let runs = tripEventGroups(in: ordered, detectedTrips: detectedTrips)
        guard runs.count > 1 else { return baseline }

        let effectiveRegion = region ?? boundingRegion(for: ordered)
        guard let effectiveRegion else { return baseline }

        let targetCount = baseline.count
        let prioritizedRuns = runs.map { candidates in
            routeCandidates(in: candidates).sorted {
                let lhsProgress = $0.progress
                let rhsProgress = $1.progress
                if abs(lhsProgress - rhsProgress) > 0.0001 {
                    return lhsProgress < rhsProgress
                }
                if $0.priority != $1.priority {
                    return $0.priority < $1.priority
                }
                return $0.detail.event.timestamp < $1.detail.event.timestamp
            }
        }

        var chosenIDs = Set<Int64>()
        var result: [EventDetail] = []
        var chosenPoints: [CGPoint] = []
        var runScores = Array(repeating: 1, count: prioritizedRuns.count)

        func point(for detail: EventDetail) -> CGPoint {
            projectedPoint(for: detail.coordinate, in: effectiveRegion, viewportSize: viewportSize)
        }

        func append(_ detail: EventDetail, requireSpacing: Bool) -> Bool {
            guard let id = detail.id, !chosenIDs.contains(id) else { return false }
            let projected = point(for: detail)
            if requireSpacing {
                guard chosenPoints.allSatisfy({ distance($0, to: projected) >= minimumSpacing }) else { return false }
            }
            chosenIDs.insert(id)
            chosenPoints.append(projected)
            result.append(detail)
            return true
        }

        func candidates(in runIndex: Int, near slotPoint: CGPoint, selectionRadius: CGFloat) -> [RouteCandidate] {
            guard prioritizedRuns.indices.contains(runIndex) else { return [] }
            let remaining = prioritizedRuns[runIndex].filter { candidate in
                guard let id = candidate.detail.id else { return false }
                return !chosenIDs.contains(id)
            }
            guard !remaining.isEmpty else { return [] }

            let nearby = remaining.filter {
                distance(point(for: $0.detail), to: slotPoint) <= selectionRadius
            }
            let pool = nearby.isEmpty ? remaining : nearby
            return pool.sorted {
                let lhsDistance = distance(point(for: $0.detail), to: slotPoint)
                let rhsDistance = distance(point(for: $1.detail), to: slotPoint)
                if abs(lhsDistance - rhsDistance) > 0.0001 {
                    return lhsDistance < rhsDistance
                }
                if $0.priority != $1.priority {
                    return $0.priority < $1.priority
                }
                return $0.detail.event.timestamp < $1.detail.event.timestamp
            }
        }

        if let first = ordered.first {
            _ = append(first, requireSpacing: false)
        }
        if let selectedEventID, let selected = ordered.first(where: { $0.id == selectedEventID }) {
            _ = append(selected, requireSpacing: false)
        }
        if let last = ordered.last {
            _ = append(last, requireSpacing: false)
        }

        let selectionRadius = minimumSpacing * 1.75
        let maxSlots = max(targetCount * 4, targetCount + 12)
        var slotIndex = 0
        while result.count < targetCount && slotIndex < maxSlots {
            let slotDetail = baseline[slotIndex % baseline.count]
            let slotPoint = point(for: slotDetail)

            let localCandidates = prioritizedRuns.indices.compactMap { runIndex -> (index: Int, candidate: RouteCandidate)? in
                guard let candidate = candidates(in: runIndex, near: slotPoint, selectionRadius: selectionRadius).first else { return nil }
                return (runIndex, candidate)
            }

            guard !localCandidates.isEmpty else {
                slotIndex += 1
                continue
            }

            let highestScore = localCandidates.map { runScores[$0.index] }.max() ?? 0
            let topCandidates = localCandidates.filter { runScores[$0.index] == highestScore }
            let chosen = topCandidates.randomElement() ?? localCandidates.randomElement()

            guard let chosen else {
                slotIndex += 1
                continue
            }

            if append(chosen.candidate.detail, requireSpacing: !result.isEmpty) {
                runScores[chosen.index] = 0
                for index in runScores.indices {
                    runScores[index] += 1
                }
            }
            slotIndex += 1
        }

        if result.count < targetCount {
            let remaining = ordered.filter { detail in
                guard let id = detail.id else { return false }
                return !chosenIDs.contains(id)
            }
            for detail in remaining {
                guard result.count < targetCount else { break }
                _ = append(detail, requireSpacing: true)
            }
        }

        return result.sorted { $0.event.timestamp < $1.event.timestamp }
    }

    private static func spacedEvents(
        within events: [EventDetail],
        selectedEventID: Int64?,
        region: MKCoordinateRegion?,
        viewportSize: CGSize,
        minimumSpacing: CGFloat
    ) -> [EventDetail] {
        let ordered = events.sorted { $0.event.timestamp < $1.event.timestamp }
        guard ordered.count > 1 else { return ordered }

        let effectiveRegion = region ?? boundingRegion(for: ordered)
        guard let effectiveRegion else {
            return ordered
        }

        var chosenIDs = Set<Int64>()
        var result: [EventDetail] = []
        var chosenPoints: [CGPoint] = []

        func append(_ detail: EventDetail, requireSpacing: Bool) {
            guard let id = detail.id, !chosenIDs.contains(id) else { return }
            let point = projectedPoint(for: detail.coordinate, in: effectiveRegion, viewportSize: viewportSize)
            if requireSpacing {
                guard chosenPoints.allSatisfy({ distance($0, to: point) >= minimumSpacing }) else { return }
            }
            chosenIDs.insert(id)
            chosenPoints.append(point)
            result.append(detail)
        }

        if let first = ordered.first {
            append(first, requireSpacing: false)
        }
        if let selectedEventID, let selected = ordered.first(where: { $0.id == selectedEventID }) {
            append(selected, requireSpacing: false)
        }
        if let last = ordered.last {
            append(last, requireSpacing: false)
        }

        func isPreferred(_ detail: EventDetail) -> Bool {
            !detail.event.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !detail.event.photoFilename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || detail.event.source != .locationServices
        }

        let remaining = ordered.filter { detail in
            guard let id = detail.id else { return false }
            return !chosenIDs.contains(id)
        }

        let prioritized = turnCandidates(in: remaining)
            + remaining.filter(isPreferred)
            + remaining

        for detail in prioritized {
            append(detail, requireSpacing: true)
        }

        return result.sorted { $0.event.timestamp < $1.event.timestamp }
    }

    private struct RouteCandidate {
        let detail: EventDetail
        let progress: Double
        let priority: Int
    }

    private static func routeCandidates(in events: [EventDetail]) -> [RouteCandidate] {
        let ordered = events.sorted { $0.event.timestamp < $1.event.timestamp }
        guard ordered.count > 1 else { return ordered.map { RouteCandidate(detail: $0, progress: 0, priority: 0) } }

        func isPreferred(_ detail: EventDetail) -> Bool {
            !detail.event.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !detail.event.photoFilename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || detail.event.source != .locationServices
        }

        let totalDistance = max(routeLength(ordered), .leastNonzeroMagnitude)
        var cumulativeDistances: [Int64: Double] = [:]
        var cumulative = 0.0
        cumulativeDistances[ordered.first?.id ?? .min] = 0
        for pair in zip(ordered, ordered.dropFirst()) {
            cumulative += distance(from: pair.0.coordinate, to: pair.1.coordinate)
            if let id = pair.1.id {
                cumulativeDistances[id] = cumulative
            }
        }

        var seen = Set<Int64>()
        var result: [RouteCandidate] = []

        func append(_ details: [EventDetail]) {
            for detail in details {
                guard let id = detail.id, !seen.contains(id) else { continue }
                seen.insert(id)
                let priority = result.count
                let progress = min(max((cumulativeDistances[id] ?? 0) / totalDistance, 0), 1)
                result.append(RouteCandidate(detail: detail, progress: progress, priority: priority))
            }
        }

        append(turnCandidates(in: ordered))
        append(ordered.filter(isPreferred))
        append(ordered)
        return result
    }

    private static func routeLength(_ events: [EventDetail]) -> Double {
        guard events.count > 1 else { return 0 }
        return zip(events, events.dropFirst()).reduce(0) { total, pair in
            total + distance(from: pair.0.coordinate, to: pair.1.coordinate)
        }
    }

    private static func tripEventGroups(in events: [EventDetail], detectedTrips: [DetectedTrip]) -> [[EventDetail]] {
        let ordered = events.sorted { $0.event.timestamp < $1.event.timestamp }
        guard ordered.count > 1 else { return [ordered] }
        guard !detectedTrips.isEmpty else { return [ordered] }

        let eventsByID = Dictionary(uniqueKeysWithValues: ordered.compactMap { detail -> (Int64, EventDetail)? in
            guard let id = detail.id else { return nil }
            return (id, detail)
        })

        let runs = detectedTrips.compactMap { trip -> [EventDetail]? in
            let tripEvents = trip.displayEventIDs.compactMap { id -> EventDetail? in
                guard let id else { return nil }
                return eventsByID[id]
            }
            guard !tripEvents.isEmpty else { return nil }
            return tripEvents.sorted { $0.event.timestamp < $1.event.timestamp }
        }

        return runs.isEmpty ? [ordered] : runs
    }

    private static func turnCandidates(in events: [EventDetail]) -> [EventDetail] {
        let ordered = events.sorted { $0.event.timestamp < $1.event.timestamp }
        guard ordered.count > 2 else { return [] }

        let candidates: [(detail: EventDetail, score: Double)] = ordered.indices.dropFirst().dropLast().compactMap { index in
            let previous = ordered[index - 1]
            let current = ordered[index]
            let next = ordered[index + 1]
            let score = turnScore(previous: previous, current: current, next: next)
            guard score > 0 else { return nil }
            return (current, score)
        }

        return candidates
            .sorted {
                if abs($0.score - $1.score) > 0.0001 {
                    return $0.score > $1.score
                }
                return $0.detail.event.timestamp < $1.detail.event.timestamp
            }
            .map(\.detail)
    }

    private static func turnScore(previous: EventDetail, current: EventDetail, next: EventDetail) -> Double {
        let incoming = bearing(from: previous.coordinate, to: current.coordinate)
        let outgoing = bearing(from: current.coordinate, to: next.coordinate)
        guard incoming.isFinite, outgoing.isFinite else { return 0 }

        let delta = abs(normalizedAngleDifference(incoming, outgoing))
        guard delta >= 25 else { return 0 }

        // Sharper turns score higher, with slight preference for real movement points.
        let movementBoost = isMovingLocationEvent(current.event) ? 1.08 : 1.0
        return delta * movementBoost
    }

    private static func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let startLat = start.latitude * .pi / 180
        let startLon = start.longitude * .pi / 180
        let endLat = end.latitude * .pi / 180
        let endLon = end.longitude * .pi / 180

        let deltaLon = endLon - startLon
        let y = sin(deltaLon) * cos(endLat)
        let x = cos(startLat) * sin(endLat) - sin(startLat) * cos(endLat) * cos(deltaLon)
        let bearing = atan2(y, x) * 180 / .pi
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }

    private static func normalizedAngleDifference(_ first: Double, _ second: Double) -> Double {
        var delta = (second - first).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    private static func distance(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let earthRadius = 6_371_000.0
        let startLat = start.latitude * .pi / 180
        let endLat = end.latitude * .pi / 180
        let deltaLat = (end.latitude - start.latitude) * .pi / 180
        let deltaLon = (end.longitude - start.longitude) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(startLat) * cos(endLat) * sin(deltaLon / 2) * sin(deltaLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadius * c
    }

    private static func boundingRegion(for events: [EventDetail]) -> MKCoordinateRegion? {
        guard let first = events.first else { return nil }
        let latitudes = events.map(\.event.latitude)
        let longitudes = events.map(\.event.longitude)
        let minLatitude = latitudes.min() ?? first.event.latitude
        let maxLatitude = latitudes.max() ?? first.event.latitude
        let minLongitude = longitudes.min() ?? first.event.longitude
        let maxLongitude = longitudes.max() ?? first.event.longitude

        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let latitudeDelta = max((maxLatitude - minLatitude) * 1.35, 0.01)
        let longitudeDelta = max((maxLongitude - minLongitude) * 1.35, 0.01)
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }

    private static func projectedPoint(
        for coordinate: CLLocationCoordinate2D,
        in region: MKCoordinateRegion,
        viewportSize: CGSize
    ) -> CGPoint {
        let width = max(viewportSize.width, 1)
        let height = max(viewportSize.height, 1)
        let longitudeMin = region.center.longitude - region.span.longitudeDelta / 2
        let latitudeMax = region.center.latitude + region.span.latitudeDelta / 2
        let xRatio = (coordinate.longitude - longitudeMin) / max(region.span.longitudeDelta, .leastNonzeroMagnitude)
        let yRatio = (latitudeMax - coordinate.latitude) / max(region.span.latitudeDelta, .leastNonzeroMagnitude)
        return CGPoint(x: xRatio * width, y: yRatio * height)
    }

    private static func distance(_ lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func isCoordinate(_ coordinate: CLLocationCoordinate2D, inside region: MKCoordinateRegion) -> Bool {
        let latitudeHalfSpan = region.span.latitudeDelta / 2
        let longitudeHalfSpan = region.span.longitudeDelta / 2
        let latitudeMin = region.center.latitude - latitudeHalfSpan
        let latitudeMax = region.center.latitude + latitudeHalfSpan
        let longitudeMin = region.center.longitude - longitudeHalfSpan
        let longitudeMax = region.center.longitude + longitudeHalfSpan
        return coordinate.latitude >= latitudeMin
            && coordinate.latitude <= latitudeMax
            && coordinate.longitude >= longitudeMin
            && coordinate.longitude <= longitudeMax
    }
}

struct EventListView: View {
    @EnvironmentObject private var model: TravelsModel
    let events: [EventDetail]

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                List {
                    ForEach(events) { detail in
                        Button {
                            model.selectedEvent = detail
                        } label: {
                            EventRow(detail: detail)
                                .padding(.horizontal)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                model.delete(detail)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .id(detail.id)
                        .background(rowVisibilityReader(for: detail))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .coordinateSpace(name: "EventListScroll")
                .onAppear {
                }
                .task(id: model.listScrollCommandID) {
                    guard let target = model.listScrollTargetEventID else { return }
                    await Task.yield()
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(target, anchor: .top)
                        }
                        model.listScrollTargetEventID = nil
                    }
                }
                .onPreferenceChange(EventListRowFramesKey.self) { frames in
                    updateVisibleEventIDs(in: geometry.size, frames: frames)
                }
            }
        }
    }

    private func rowVisibilityReader(for detail: EventDetail) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: EventListRowFramesKey.self,
                value: [detail.id ?? .min: proxy.frame(in: .named("EventListScroll"))]
            )
        }
    }

    private func updateVisibleEventIDs(in viewportSize: CGSize, frames: [Int64: CGRect] = [:]) {
        let currentFrames = frames.isEmpty ? EventListRowFramesKey.defaultValue : frames
        let viewport = CGRect(origin: .zero, size: viewportSize)
        let visibleIDs = events.compactMap { detail -> Int64? in
            guard let id = detail.id, let frame = currentFrames[id] else { return nil }
            guard frame.intersects(viewport) else { return nil }
            return id
        }
        model.updateListVisibleEventIDs(visibleIDs)
    }
}

private struct EventListRowFramesKey: PreferenceKey {
    static let defaultValue: [Int64: CGRect] = [:]

    static func reduce(value: inout [Int64: CGRect], nextValue: () -> [Int64: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct EventRow: View {
    @EnvironmentObject private var model: TravelsModel
    let detail: EventDetail

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color(for: detail))
                .frame(width: 6)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    rowGlyph("clock")
                        .offset(y: -1)
                    Text(timeText)
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    rowGlyph(symbol(for: detail.event.source))
                    Text(coordinateText(latitude: detail.event.latitude, longitude: detail.event.longitude))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    rowGlyph("scope")
                    Text(detail.event.horizontalAccuracy >= 0 ? formattedLengthText(detail.event.horizontalAccuracy, measurementSystem: model.settings.preferredMeasurementSystem, naturalScale: false) : "Unknown")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    rowGlyph(addressIcon)
                    Text(primaryText)
                        .font(.headline)
                }
                if !detail.event.note.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        rowGlyph("note.text")
                        Text(detail.event.note)
                            .font(.subheadline)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var primaryText: String {
        if let geolocation = detail.geolocation {
            let street = "\(geolocation.subThoroughfare) \(geolocation.thoroughfare)".trimmingCharacters(in: .whitespaces)
            if !geolocation.name.isEmpty { return geolocation.name }
            if !street.isEmpty { return street }
            if !geolocation.locality.isEmpty { return geolocation.locality }
        }
        return "Unknown Place"
    }

    private var addressIcon: String {
        detail.geolocation == nil ? "house" : "house.fill"
    }

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        if let identifier = detail.geolocation?.timeZoneIdentifier, let timeZone = TimeZone(identifier: identifier) {
            formatter.timeZone = timeZone
        }
        return formatter.string(from: detail.event.timestamp)
    }

    private func rowGlyph(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .regular))
            .frame(width: 18, height: 18, alignment: .center)
            .foregroundStyle(.secondary)
    }
}

struct EventDetailView: View {
    @EnvironmentObject private var model: TravelsModel
    let detail: EventDetail
    @State private var note: String
    @State private var confirmDelete = false

    init(detail: EventDetail) {
        self.detail = detail
        _note = State(initialValue: detail.event.note)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Map {
                        Marker(primaryText, coordinate: detail.coordinate)
                    }
                    .frame(height: 180)
                }

                Section("Note") {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $note)
                            .frame(minHeight: 100)
                            .scrollContentBackground(.hidden)
                        if !EventDetailDisplayRules.isMeaningfulDisplayText(note) {
                            Text("Add a note")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                        }
                    }
                }

                Section("Event") {
                    labeled("Latitude", coordinateText(detail.event.latitude))
                    labeled("Longitude", coordinateText(detail.event.longitude))
                    if EventDetailDisplayRules.hasMeaningfulAccuracy(detail.event.horizontalAccuracy) {
                        labeled("Horizontal Accuracy", formattedPrecisionLength(detail.event.horizontalAccuracy) ?? "")
                    }
                    if EventDetailDisplayRules.hasMeaningfulAccuracy(detail.event.verticalAccuracy) {
                        labeled("Vertical Accuracy", formattedPrecisionLength(detail.event.verticalAccuracy) ?? "")
                    }
                    if EventDetailDisplayRules.hasMeaningfulAltitude(detail.event.altitude) {
                        labeled("Altitude", formattedPrecisionLength(detail.event.altitude) ?? "")
                    }
                    if EventDetailDisplayRules.hasMeaningfulCourse(detail.event.course) {
                        labeled("Course", formattedAngle(detail.event.course) ?? "")
                    }
                    if EventDetailDisplayRules.hasMeaningfulSpeed(detail.event.speed) {
                        labeled("Speed", formattedSpeed(detail.event.speed) ?? "")
                    }
                    labeled("Timestamp", formattedTimestamp(detail.event.timestamp, timeZoneIdentifier: detail.geolocation?.timeZoneIdentifier))
                    if let localizedDate = EventDetailDisplayRules.normalizedDisplayText(detail.event.localizedDate) {
                        labeled("Localized Date", localizedDate)
                    }
                    if EventDetailDisplayRules.hasMeaningfulSolarPeriod(detail.event.solarPeriod) {
                        labeled("Time of Day", timeOfDayText)
                    }
                    labeled("Source", detail.event.source.displayName)
                    if let tags = EventDetailDisplayRules.normalizedDisplayText(detail.event.tags) {
                        labeled("Tags", tags)
                    }
                    if let externalReference = EventDetailDisplayRules.normalizedDisplayText(detail.event.externalReference) {
                        labeled("External Reference", externalReference)
                    }
                    if let photoFilename = EventDetailDisplayRules.normalizedDisplayText(detail.event.photoFilename) {
                        labeled("Photo", photoFilename)
                    }
                }

                if let geolocation = detail.geolocation,
                   EventDetailDisplayRules.hasMeaningfulPlaceMetadata(geolocation) {
                    Section("Geolocation") {
                        geolocationFallbackField("Latitude", eventValue: coordinateText(detail.event.latitude), geolocationValue: coordinateText(geolocation.latitude))
                        geolocationFallbackField("Longitude", eventValue: coordinateText(detail.event.longitude), geolocationValue: coordinateText(geolocation.longitude))
                        if geolocation.radius > 0 {
                            labeled("Radius", formattedLength(geolocation.radius))
                        }
                        geolocationFallbackField("Horizontal Accuracy", eventValue: formattedPrecisionLength(detail.event.horizontalAccuracy), geolocationValue: formattedPrecisionLength(geolocation.horizontalAccuracy))
                        geolocationFallbackField("Vertical Accuracy", eventValue: formattedPrecisionLength(detail.event.verticalAccuracy), geolocationValue: formattedPrecisionLength(geolocation.verticalAccuracy))
                        geolocationFallbackField("Altitude", eventValue: formattedPrecisionLength(detail.event.altitude), geolocationValue: formattedPrecisionLength(geolocation.altitude))
                        geolocationFallbackField(
                            "Timestamp",
                            eventValue: formattedTimestamp(detail.event.timestamp, timeZoneIdentifier: detail.geolocation?.timeZoneIdentifier),
                            geolocationValue: geolocation.timestamp.map { formattedTimestamp($0, timeZoneIdentifier: geolocation.timeZoneIdentifier) }
                        )
                        if let minLatitude = geolocation.minLatitude {
                            labeled("Min Latitude", coordinateText(minLatitude))
                        }
                        if let maxLatitude = geolocation.maxLatitude {
                            labeled("Max Latitude", coordinateText(maxLatitude))
                        }
                        if let minLongitude = geolocation.minLongitude {
                            labeled("Min Longitude", coordinateText(minLongitude))
                        }
                        if let maxLongitude = geolocation.maxLongitude {
                            labeled("Max Longitude", coordinateText(maxLongitude))
                        }
                        if EventDetailDisplayRules.isMeaningfulDisplayText(geolocation.identifier) {
                            labeled("Identifier", geolocation.identifier)
                        }
                        if EventDetailDisplayRules.isMeaningfulDisplayText(geolocation.timeZoneIdentifier) {
                            labeled("Time Zone Identifier", geolocation.timeZoneIdentifier)
                        }
                        if EventDetailDisplayRules.isMeaningfulDisplayText(geolocation.name) {
                            labeled("Name", geolocation.name)
                        }
                        if EventDetailDisplayRules.isMeaningfulDisplayText(geolocation.subThoroughfare) {
                            labeled("SubThoroughfare", geolocation.subThoroughfare)
                        }
                        if EventDetailDisplayRules.isMeaningfulDisplayText(geolocation.thoroughfare) {
                            labeled("Thoroughfare", geolocation.thoroughfare)
                        }
                        if EventDetailDisplayRules.isMeaningfulDisplayText(geolocation.subLocality) {
                            labeled("SubLocality", geolocation.subLocality)
                        }
                        if EventDetailDisplayRules.isMeaningfulDisplayText(geolocation.locality) {
                            labeled("Locality", geolocation.locality)
                        }
                        if EventDetailDisplayRules.isMeaningfulDisplayText(geolocation.subAdministrativeArea) {
                            labeled("SubAdministrativeArea", geolocation.subAdministrativeArea)
                        }
                        if EventDetailDisplayRules.isMeaningfulDisplayText(geolocation.administrativeArea) {
                            labeled("AdministrativeArea", geolocation.administrativeArea)
                        }
                        if EventDetailDisplayRules.isMeaningfulDisplayText(geolocation.postalCode) {
                            labeled("Postal Code", geolocation.postalCode)
                        }
                        if EventDetailDisplayRules.isMeaningfulDisplayText(geolocation.isoCountryCode) {
                            labeled("ISO Country Code", geolocation.isoCountryCode)
                        }
                        if EventDetailDisplayRules.isMeaningfulDisplayText(geolocation.country) {
                            labeled("Country", geolocation.country)
                        }
                        if EventDetailDisplayRules.isMeaningfulDisplayText(geolocation.inlandWater) {
                            labeled("Inland Water", geolocation.inlandWater)
                        }
                        if EventDetailDisplayRules.isMeaningfulDisplayText(geolocation.ocean) {
                            labeled("Ocean", geolocation.ocean)
                        }
                        if EventDetailDisplayRules.hasMeaningfulAreasOfInterest(geolocation.areasOfInterest) {
                            labeled("Areas Of Interest", geolocation.areasOfInterest.filter { EventDetailDisplayRules.isMeaningfulDisplayText($0) }.joined(separator: "\n"))
                        }
                    }
                }

                if needsAddressResolution {
                    Section {
                        Button("Resolve Address Now") {
                            Task {
                                await model.resolveAddress(for: detail)
                            }
                        }
                    }
                }

                if let url = model.photoURL(for: detail), let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                    Section("Photo") {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                Section {
                    Button("Open in Maps") {
                        openInMaps()
                    }
                    Button("Delete Event", role: .destructive) {
                        confirmDelete = true
                    }
                }
            }
            .navigationTitle("Details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.updateNote(for: detail, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
                        model.selectedEvent = nil
                    }
                }
            }
            .confirmationDialog("Delete this event?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    model.delete(detail)
                }
            }
        }
    }

    private var primaryText: String {
        if let name = EventDetailDisplayRules.normalizedDisplayText(detail.geolocation?.name) { return name }
        return "Location"
    }

    private var timeOfDayText: String {
        timeOfDayColorResolver.displayText(for: detail)
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value.isEmpty ? " " : value)
        }
    }

    private func formattedTimestamp(_ date: Date, timeZoneIdentifier: String?) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        if let identifier = timeZoneIdentifier, let timeZone = TimeZone(identifier: identifier) {
            formatter.timeZone = timeZone
        }
        return formatter.string(from: date)
    }

    private func openInMaps() {
        let coordinate = detail.coordinate
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = primaryText
        item.openInMaps()
    }

    private var needsAddressResolution: Bool {
        guard let geolocation = detail.geolocation else { return true }
        return geolocation.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var measurementSystem: MeasurementSystemPreference {
        model.settings.preferredMeasurementSystem
    }

    @ViewBuilder
    private func geolocationFallbackField(_ title: String, eventValue: String?, geolocationValue: String?) -> some View {
        if EventDetailDisplayRules.normalizedDisplayText(eventValue) == nil,
           let geolocationValue = EventDetailDisplayRules.normalizedDisplayText(geolocationValue) {
            labeled(title, geolocationValue)
        }
    }

    private func formattedPrecisionLength(_ meters: Double) -> String? {
        guard meters >= 0 else { return nil }
        let formatter = measurementFormatter(unitOptions: .providedUnit)
        let measurement: Measurement<UnitLength>
        switch measurementSystem {
        case .metric:
            measurement = Measurement(value: meters, unit: .meters)
        case .imperial:
            measurement = Measurement(value: meters * 3.280_839_895_013_123, unit: .feet)
        }
        return formatter.string(from: measurement)
    }

    private func formattedLength(_ meters: Double) -> String {
        let formatter = measurementFormatter()
        let measurement: Measurement<UnitLength>
        switch measurementSystem {
        case .metric:
            measurement = Measurement(value: meters, unit: .meters)
        case .imperial:
            measurement = Measurement(value: meters, unit: .feet)
        }
        return formatter.string(from: measurement)
    }

    private func formattedSpeed(_ metersPerSecond: Double) -> String? {
        guard metersPerSecond >= 0 else { return nil }
        let formatter = measurementFormatter(unitOptions: .providedUnit)
        let measurement: Measurement<UnitSpeed>
        switch measurementSystem {
        case .metric:
            measurement = Measurement(value: metersPerSecond * 3.6, unit: .kilometersPerHour)
        case .imperial:
            measurement = Measurement(value: metersPerSecond * 2.236_936_292_054_4, unit: .milesPerHour)
        }
        return formatter.string(from: measurement)
    }

    private func formattedAngle(_ degrees: Double) -> String? {
        guard degrees >= 0 else { return nil }
        return String(format: "%.2f°", degrees)
    }

    private func measurementFormatter(unitOptions: MeasurementFormatter.UnitOptions = .naturalScale) -> MeasurementFormatter {
        let formatter = MeasurementFormatter()
        formatter.locale = .current
        formatter.unitStyle = .short
        formatter.unitOptions = unitOptions
        formatter.numberFormatter.numberStyle = .decimal
        formatter.numberFormatter.minimumFractionDigits = 2
        formatter.numberFormatter.maximumFractionDigits = 2
        return formatter
    }
}

extension EventDetail {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: event.latitude, longitude: event.longitude)
    }
}

private struct RouteSegment: Identifiable {
    let id: String
    let coordinates: [CLLocationCoordinate2D]
    let color: Color
}

private struct EventMapBadge: View {
    let detail: EventDetail

    var body: some View {
        let color = color(for: detail)
        let rotation = badgeRotation(for: detail)

        if let rotation {
            DirectionPointer(color: color)
                .scaleEffect(x: 0.92, y: 1.14)
                .rotationEffect(.degrees(rotation))
        } else {
            Image(systemName: symbol(for: detail.event.source))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(color)
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                }
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.18), radius: 1.5, x: 0, y: 1)
        }
    }
}

private struct DirectionPointer: View {
    let color: Color

    var body: some View {
        ZStack {
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 0.9, x: 0, y: 0.5)
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
        }
        .shadow(color: .black.opacity(0.12), radius: 1.0, x: 0, y: 0.75)
    }
}

func symbol(for source: EventSource) -> String {
    switch source {
    case .locationServices: "location.circle.fill"
    case .imported: "square.and.arrow.down"
    case .photo: "photo"
    case .manual: "mappin"
    case .invalid: "questionmark"
    case .simulated: "simcard"
    }
}

private func badgeRotation(for detail: EventDetail) -> Double? {
    guard isMovingLocationEvent(detail.event), detail.event.course >= 0 else { return nil }
    return detail.event.course.truncatingRemainder(dividingBy: 360)
}

func color(for detail: EventDetail) -> Color {
    Color(timeOfDayColorResolver.color(for: detail))
}

private func coordinateText(_ value: Double) -> String {
    String(format: "%.6f", value)
}

private func coordinateText(latitude: Double, longitude: Double) -> String {
    "\(coordinateText(latitude)), \(coordinateText(longitude))"
}

func formattedLengthText(_ meters: Double, measurementSystem: MeasurementSystemPreference, naturalScale: Bool = true) -> String {
    let formatter = NumberFormatter()
    formatter.locale = .current
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2

    func valueString(_ value: Double) -> String {
        formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    switch measurementSystem {
    case .metric:
        return "\(valueString(meters)) m"
    case .imperial:
        let milesThreshold = 1609.344
        if naturalScale && abs(meters) >= milesThreshold {
            return "\(valueString(meters / milesThreshold)) mi"
        } else {
            return "\(valueString(meters * 3.280_839_895_013_123)) ft"
        }
    }
}

func formattedSpeedText(_ metersPerSecond: Double, measurementSystem: MeasurementSystemPreference) -> String {
    let formatter = MeasurementFormatter()
    formatter.locale = .current
    formatter.unitStyle = .short
    formatter.unitOptions = .providedUnit
    formatter.numberFormatter.numberStyle = .decimal
    formatter.numberFormatter.minimumFractionDigits = 2
    formatter.numberFormatter.maximumFractionDigits = 2

    let measurement: Measurement<UnitSpeed>
    switch measurementSystem {
    case .metric:
        measurement = Measurement(value: metersPerSecond * 3.6, unit: .kilometersPerHour)
    case .imperial:
        measurement = Measurement(value: metersPerSecond * 2.236_936_292_054_4, unit: .milesPerHour)
    }
    return formatter.string(from: measurement)
}

func formattedAngleText(_ degrees: Double) -> String {
    String(format: "%.2f°", degrees)
}
