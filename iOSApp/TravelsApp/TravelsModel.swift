// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import LocalAuthentication
import MapKit
import SwiftUI

#if canImport(TravelsCore)
import TravelsCore
#endif

@MainActor
final class TravelsModel: ObservableObject {
    @Published var selectedDate = Calendar.current.startOfDay(for: Date())
    @Published var events: [EventDetail] = []
    @Published var selectedEvent: EventDetail?
    @Published var settings = AppSettings()
    @Published var isListView = false
    @Published var isUnlocked = true
    @Published var statusMessage: String?
    @Published var searchResults: [EventDetail] = []
    @Published var addressResolutionLog: [String] = []
    @Published var addressResolutionStatus = "Idle"
    @Published var addressResolutionPendingCount = 0
    @Published var addressResolutionLastRunAt: Date?
    @Published var addressResolutionLastSuccessAt: Date?
    @Published var addressResolutionLastError: String?
    @Published var addressResolutionCurrentTarget: String?

    private var store: TravelsStore?
    private var settingsStore: SettingsStore?
    private let locationService = LocationTrackingService()
    private var appSupportURL: URL?
    private var addressResolutionTask: Task<Void, Never>?
    private var addressResolutionNeedsRerun = false

    func bootstrap() async {
        do {
            let bootstrapDate = Date()
            let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            let appSupport = urls[0].appendingPathComponent("Travels", isDirectory: true)
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: appSupport.appendingPathComponent("Photos", isDirectory: true),
                withIntermediateDirectories: true
            )
            appSupportURL = appSupport
            let storeURL = appSupport.appendingPathComponent("Travels.sqlite")
            let store = try TravelsStore(url: storeURL)
            self.store = store
            self.settingsStore = SettingsStore(store: store)
            self.settings = try settingsStore?.load() ?? AppSettings()
            self.isListView = settings.preferListView
            try await importLegacyDatabaseIfNeeded(appSupport: appSupport, store: store)
            try ensureDemoReferenceDate(referenceDate: bootstrapDate)
            try seedDemoDataIfNeeded()
            try reloadEvents()
            try focusOnDemoDataIfNeeded()
            locationService.onStatusMessage = { [weak self] message in
                self?.statusMessage = message
            }
            locationService.onTrackedEvent = { [weak self] in
                guard let self else { return }
                do {
                    try reloadEvents()
                    requestAddressResolution()
                } catch {
                    statusMessage = error.localizedDescription
                }
            }
            locationService.configure(store: store, settings: settings, latestEvent: events.last?.event)
            requestAddressResolution()
            if settings.requireAuthentication {
                isUnlocked = false
                authenticate()
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func reloadEvents() throws {
        guard let store else { return }
        events = try store.events(
            on: selectedDate,
            includePreviousDayContext: settings.includePreviousDayContext,
            includeDemo: settings.includeDemoData
        )
        refreshSelectedEventIfNeeded()
    }

    func selectDate(_ date: Date) {
        selectedDate = Calendar.current.startOfDay(for: date)
        do {
            try reloadEvents()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func saveSettings() {
        do {
            settings.preferListView = isListView
            try settingsStore?.save(settings)
            locationService.update(settings: settings)
            if settings.includeDemoData {
                try ensureDemoReferenceDate(referenceDate: Date())
                try seedDemoDataIfNeeded()
                try reloadEvents()
                try focusOnDemoDataIfNeeded()
            } else {
                try reloadEvents()
            }
            requestAddressResolution()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func search(_ criteria: SearchCriteria) {
        do {
            searchResults = try store?.search(criteria, includeDemo: settings.includeDemoData) ?? []
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func searchPlaceOptions() -> SearchPlaceOptions {
        do {
            let details = try store?.allEvents(includeDemo: settings.includeDemoData) ?? []
            return SearchPlaceOptions(
                countries: uniquePlaceValues(details.compactMap { nonEmpty($0.geolocation?.country) }),
                administrativeAreas: uniquePlaceValues(details.compactMap { nonEmpty($0.geolocation?.administrativeArea) }),
                subAdministrativeAreas: uniquePlaceValues(details.compactMap { nonEmpty($0.geolocation?.subAdministrativeArea) }),
                localities: uniquePlaceValues(details.compactMap { nonEmpty($0.geolocation?.locality) }),
                bodyOfWaters: uniquePlaceValues(details.compactMap {
                    nonEmpty($0.geolocation?.inlandWater) ?? nonEmpty($0.geolocation?.ocean)
                })
            )
        } catch {
            statusMessage = error.localizedDescription
            return .empty
        }
    }

    func allEventDetails() -> [EventDetail] {
        do {
            return try store?.allEvents(includeDemo: settings.includeDemoData) ?? []
        } catch {
            statusMessage = error.localizedDescription
            return []
        }
    }

    func dateSelectionRange() -> ClosedRange<Date> {
        let today = Calendar.current.startOfDay(for: Date())
        guard let store else {
            return today...today
        }
        do {
            let oldest = try store.oldestEventDate(includeDemo: settings.includeDemoData)
            let lowerBound = Calendar.current.startOfDay(for: oldest ?? today)
            let upperBound = max(lowerBound, today)
            return lowerBound...upperBound
        } catch {
            return today...today
        }
    }

    func clampedDateSelection(_ date: Date) -> Date {
        let range = dateSelectionRange()
        return min(max(Calendar.current.startOfDay(for: date), range.lowerBound), range.upperBound)
    }

    func updateNote(for detail: EventDetail, note: String) {
        guard let id = detail.event.id else { return }
        do {
            try store?.updateNote(eventID: id, note: note)
            try reloadEvents()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func resolveAddress(for detail: EventDetail) async {
        guard let store, let eventID = detail.event.id else { return }
        do {
            let location = CLLocation(
                latitude: detail.event.latitude,
                longitude: detail.event.longitude
            )
            let result = await ReverseGeocodingService.shared.lookup(for: location, store: store)
            logAddressResolution(detail: detail, result: result)
            guard let geolocation = result.geolocation,
                  let geolocationID = geolocation.id else {
                statusMessage = "Could not resolve this location."
                return
            }
            try store.attachGeolocation(geolocationID, toEvent: eventID)
            addressResolutionLastSuccessAt = Date()
            addressResolutionLastError = nil
            try reloadEvents()
            requestAddressResolution()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func delete(_ detail: EventDetail) {
        guard let id = detail.event.id else { return }
        do {
            try store?.deleteEvent(eventID: id)
            removePhotoAttachment(for: detail)
            try reloadEvents()
            selectedEvent = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func importGPX(url: URL) {
        do {
            guard let store else { return }
            let result = try GPXImporter.parse(url: url)
            for event in result.events {
                _ = try store.saveEvent(event)
            }
            try reloadEvents()
            requestAddressResolution()
            statusMessage = "Imported \(result.events.count) events"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func importPhoto(data: Data, note: String = "") {
        do {
            guard let store, let photoURL = makePhotoURL() else { return }
            try data.write(to: photoURL, options: [.atomic])
            let timestamp = Calendar.current.date(byAdding: .hour, value: 12, to: selectedDate) ?? Date()
            let anchor = events.last
            let event = LocationEvent(
                latitude: anchor?.event.latitude ?? 0,
                longitude: anchor?.event.longitude ?? 0,
                timestamp: timestamp,
                localizedDate: TravelsDateTools.localizedDayString(for: timestamp, timeZoneIdentifier: nil),
                source: .photo,
                geolocationID: anchor?.event.geolocationID,
                note: note,
                photoFilename: photoURL.lastPathComponent
            )
            _ = try store.saveEvent(event)
            try reloadEvents()
            statusMessage = "Imported photo"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func photoURL(for detail: EventDetail) -> URL? {
        guard let filename = nonEmpty(detail.event.photoFilename), let appSupportURL else { return nil }
        return appSupportURL.appendingPathComponent("Photos", isDirectory: true).appendingPathComponent(filename)
    }

    func exportCurrentDayGPX() -> URL? {
        do {
            guard let store else { return nil }
            let items = try store.events(
                on: selectedDate,
                includePreviousDayContext: settings.includePreviousDayContext,
                includeDemo: settings.includeDemoData
            )
            let xml = try GPXExporter.export(events: items)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let name = "Travels-\(formatter.string(from: selectedDate)).gpx"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try xml.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }
    }

#if DEBUG
    func rerunAddressResolutionQueue() {
        requestAddressResolution()
    }

    func clearAddressResolutionLog() {
        addressResolutionLog.removeAll()
    }
#endif

    func authenticate() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isUnlocked = true
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Please authenticate to use Travels.") { success, _ in
            Task { @MainActor in
                self.isUnlocked = success
            }
        }
    }

    private func importLegacyDatabaseIfNeeded(appSupport: URL, store: TravelsStore) async throws {
        if try store.setting("migration.legacyTravelsSQLite.complete") == "true" {
            return
        }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let legacyURL = documents.appendingPathComponent("travels.sqlite")
        guard FileManager.default.fileExists(atPath: legacyURL.path) else {
            return
        }
        let backupURL = appSupport.appendingPathComponent("travels.sqlite.pre-modernization-backup")
        if !FileManager.default.fileExists(atPath: backupURL.path) {
            try FileManager.default.copyItem(at: legacyURL, to: backupURL)
        }
        let importer = LegacyTravelsImporter(destination: store)
        let summary = try importer.importDatabase(at: legacyURL)
        statusMessage = "Migrated \(summary.importedEvents) legacy events"
    }

    private func ensureDemoReferenceDate(referenceDate: Date) throws {
        guard let store else { return }
        if try store.setting("demo.firstLaunchDate") == nil {
            try store.setSetting("demo.firstLaunchDate", value: String(referenceDate.timeIntervalSinceReferenceDate))
        }
    }

    private func demoReferenceDate() throws -> Date {
        guard let store else { return Date() }
        if let value = try store.setting("demo.firstLaunchDate"), let interval = Double(value) {
            return Date(timeIntervalSinceReferenceDate: interval)
        }
        let now = Date()
        try store.setSetting("demo.firstLaunchDate", value: String(now.timeIntervalSinceReferenceDate))
        return now
    }

    private func seedDemoDataIfNeeded() throws {
        guard let store else { return }
        guard settings.includeDemoData else { return }
        guard try store.eventCount(includeDemo: false) == 0 else { return }
        guard try store.setting("demo.seeded.complete") != "true" else { return }
        let referenceDate = try demoReferenceDate()
        try DemoData.seed(into: store, anchoredTo: referenceDate)
        try store.setSetting("demo.seeded.complete", value: "true")
    }

    private func focusOnDemoDataIfNeeded() throws {
        guard let store else { return }
        guard settings.includeDemoData else { return }
        guard try store.eventCount(includeDemo: false) == 0 else { return }
        guard let latestVisibleDate = try store.latestEventDate(includeDemo: true) else { return }
        selectedDate = Calendar.current.startOfDay(for: latestVisibleDate)
        try reloadEvents()
    }

    private func requestAddressResolution() {
        guard settings.resolveAddresses || settings.resolveMissingAddresses else { return }
        addressResolutionNeedsRerun = true
        addressResolutionStatus = "Queued"
        appendAddressResolutionLog("Queued address resolution")
        guard addressResolutionTask == nil else { return }
        addressResolutionTask = Task { @MainActor [weak self] in
            await self?.processAddressResolutionQueue()
        }
    }

    private func processAddressResolutionQueue() async {
        defer {
            addressResolutionTask = nil
            addressResolutionStatus = "Idle"
            addressResolutionCurrentTarget = nil
            addressResolutionPendingCount = 0
        }

        repeat {
            addressResolutionNeedsRerun = false
            addressResolutionStatus = "Running"
            addressResolutionLastRunAt = Date()
            await resolveMissingAddressesIfNeeded()
        } while addressResolutionNeedsRerun
    }

    private func resolveMissingAddressesIfNeeded() async {
        guard settings.resolveAddresses || settings.resolveMissingAddresses, let store else { return }
        do {
            var resolvedCount = 0
            var processedEventIDs = Set<Int64>()
            while true {
                let unresolved = try store.eventsNeedingGeolocation(includeDemo: settings.includeDemoData)
                    .sorted { $0.event.timestamp > $1.event.timestamp }
                    .filter { detail in
                        guard let id = detail.event.id else { return true }
                        return !processedEventIDs.contains(id)
                    }
                addressResolutionPendingCount = unresolved.count
                guard let detail = unresolved.first, let eventID = detail.event.id else {
                    break
                }
                addressResolutionCurrentTarget = addressResolutionLabel(for: detail)
                appendAddressResolutionLog("Resolving \(addressResolutionCurrentTarget ?? "unknown event")")
                let location = CLLocation(
                    latitude: detail.event.latitude,
                    longitude: detail.event.longitude
                )
                let result = await ReverseGeocodingService.shared.lookup(for: location, store: store)
                logAddressResolution(detail: detail, result: result)
                guard let geolocation = result.geolocation else {
                    processedEventIDs.insert(eventID)
                    continue
                }
                processedEventIDs.insert(eventID)
                if let geolocationID = geolocation.id {
                    try store.attachGeolocation(geolocationID, toEvent: eventID)
                    resolvedCount += 1
                    addressResolutionLastSuccessAt = Date()
                    addressResolutionLastError = nil
                    try reloadEvents()
                }
            }

            if resolvedCount > 0 {
                try reloadEvents()
            }
        } catch {
            addressResolutionLastError = error.localizedDescription
            appendAddressResolutionLog("Queue failed: \(error.localizedDescription)")
            statusMessage = error.localizedDescription
        }
    }

    private func makePhotoURL() -> URL? {
        guard let appSupportURL else { return nil }
        let photos = appSupportURL.appendingPathComponent("Photos", isDirectory: true)
        let name = "photo-\(UUID().uuidString).img"
        return photos.appendingPathComponent(name)
    }

    private func removePhotoAttachment(for detail: EventDetail) {
        guard let photoURL = photoURL(for: detail), FileManager.default.fileExists(atPath: photoURL.path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: photoURL)
        } catch {
            statusMessage = "Deleted the event, but could not remove the saved photo."
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private func uniquePlaceValues(_ values: [String]) -> [String] {
        Array(Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }

    private func refreshSelectedEventIfNeeded() {
        guard let selectedEvent, let id = selectedEvent.id else { return }
        self.selectedEvent = events.first(where: { $0.id == id }) ?? selectedEvent
    }

    private func addressResolutionLabel(for detail: EventDetail) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        let timestamp = dateFormatter.string(from: detail.event.timestamp)
        return "Event \(detail.event.id ?? 0) @ \(timestamp)"
    }

    private func logAddressResolution(detail: EventDetail, result: ReverseGeocodingLookupResult) {
        let label = addressResolutionLabel(for: detail)
        let waited = result.waitedSeconds > 0 ? String(format: "%.1fs", result.waitedSeconds) : "no wait"
        let outcome = result.geolocation == nil ? "unresolved" : "resolved"
        appendAddressResolutionLog("\(label): \(outcome) via \(result.source.rawValue), \(waited) - \(result.summary)")
        if let errorDescription = result.errorDescription {
            addressResolutionLastError = errorDescription
        }
    }

    private func appendAddressResolutionLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let entry = "[\(formatter.string(from: Date()))] \(message)"
        addressResolutionLog.append(entry)
        if addressResolutionLog.count > 100 {
            addressResolutionLog.removeFirst(addressResolutionLog.count - 100)
        }
    }
}

struct SearchPlaceOptions: Equatable {
    var countries: [String]
    var administrativeAreas: [String]
    var subAdministrativeAreas: [String]
    var localities: [String]
    var bodyOfWaters: [String]

    static let empty = SearchPlaceOptions(
        countries: [],
        administrativeAreas: [],
        subAdministrativeAreas: [],
        localities: [],
        bodyOfWaters: []
    )
}
