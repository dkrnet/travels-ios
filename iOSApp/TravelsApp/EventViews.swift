// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import MapKit
import SwiftUI
import UIKit

#if canImport(TravelsCore)
import TravelsCore
#endif

struct EventMapView: View {
    @EnvironmentObject private var model: TravelsModel
    let events: [EventDetail]

    var body: some View {
        Map {
            ForEach(routeSegments) { segment in
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(segment.color, lineWidth: 3)
            }
            ForEach(events) { detail in
                Annotation(markerTitle(for: detail), coordinate: detail.coordinate) {
                    Button {
                        model.selectedEvent = detail
                    } label: {
                        Image(systemName: symbol(for: detail.event.source))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(color(for: detail))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var routeSegments: [RouteSegment] {
        guard events.count > 1 else { return [] }
        return events.indices.dropLast().map { index in
            RouteSegment(
                id: "\(index)-\(index + 1)",
                coordinates: [events[index].coordinate, events[index + 1].coordinate],
                color: color(for: events[index + 1]).opacity(0.9)
            )
        }
    }

    private func markerTitle(for detail: EventDetail) -> String {
        if let name = detail.geolocation?.name, !name.isEmpty {
            return name
        }
        return String(format: "%.4f, %.4f", detail.event.latitude, detail.event.longitude)
    }
}

struct EventListView: View {
    @EnvironmentObject private var model: TravelsModel
    let events: [EventDetail]

    var body: some View {
        List(events) { detail in
            Button {
                model.selectedEvent = detail
            } label: {
                EventRow(detail: detail)
            }
            .buttonStyle(.plain)
        }
    }
}

struct EventRow: View {
    let detail: EventDetail

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color(for: detail))
                .frame(width: 6)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(timeText, systemImage: "clock")
                    Spacer()
                    Label(detail.event.source.displayName, systemImage: symbol(for: detail.event.source))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(primaryText)
                    .font(.headline)
                Text(String(format: "%.6f, %.6f", detail.event.latitude, detail.event.longitude))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !detail.event.note.isEmpty {
                    Text(detail.event.note)
                        .font(.subheadline)
                        .lineLimit(2)
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

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        if let identifier = detail.geolocation?.timeZoneIdentifier, let timeZone = TimeZone(identifier: identifier) {
            formatter.timeZone = timeZone
        }
        return formatter.string(from: detail.event.timestamp)
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
                    TextEditor(text: $note)
                        .frame(minHeight: 100)
                }

                Section("Location") {
                    labeled("Name", primaryText)
                    labeled("Coordinates", String(format: "%.6f, %.6f", detail.event.latitude, detail.event.longitude))
                    labeled("Accuracy", detail.event.horizontalAccuracy >= 0 ? "\(Int(detail.event.horizontalAccuracy.rounded())) m" : "Unknown")
                    labeled("Source", detail.event.source.displayName)
                    labeled("Time Zone", detail.geolocation?.timeZoneIdentifier ?? "")
                    labeled("Country", detail.geolocation?.country ?? "")
                    labeled("Administrative Area", detail.geolocation?.administrativeArea ?? "")
                    labeled("Locality", detail.geolocation?.locality ?? "")
                    labeled("Body of Water", bodyOfWater)
                    if let areas = detail.geolocation?.areasOfInterest, !areas.isEmpty {
                        labeled("Areas of Interest", areas.joined(separator: "\n"))
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
        if let name = detail.geolocation?.name, !name.isEmpty { return name }
        return "Location"
    }

    private var bodyOfWater: String {
        if let inlandWater = detail.geolocation?.inlandWater, !inlandWater.isEmpty { return inlandWater }
        if let ocean = detail.geolocation?.ocean, !ocean.isEmpty { return ocean }
        return ""
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value.isEmpty ? " " : value)
        }
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

func color(for detail: EventDetail) -> Color {
    let formatter = DateFormatter()
    formatter.dateFormat = "H"
    if let identifier = detail.geolocation?.timeZoneIdentifier, let timeZone = TimeZone(identifier: identifier) {
        formatter.timeZone = timeZone
    }
    let hour = Int(formatter.string(from: detail.event.timestamp)) ?? 0
    switch hour {
    case 6...8: return Color.yellow
    case 9...14: return Color.blue
    case 15...17: return Color.purple
    case 18...20: return Color.red
    default: return Color.gray
    }
}
