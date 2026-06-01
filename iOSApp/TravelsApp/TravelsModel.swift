// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import LocalAuthentication
import MapKit
import SwiftUI
import TravelsCore

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

    private var store: TravelsStore?
    private var settingsStore: SettingsStore?

    func bootstrap() async {
        do {
            let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            let appSupport = urls[0].appendingPathComponent("Travels", isDirectory: true)
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            let storeURL = appSupport.appendingPathComponent("Travels.sqlite")
            let store = try TravelsStore(url: storeURL)
            self.store = store
            self.settingsStore = SettingsStore(store: store)
            self.settings = try settingsStore?.load() ?? AppSettings()
            self.isListView = settings.preferListView
            try await importLegacyDatabaseIfNeeded(appSupport: appSupport, store: store)
            try reloadEvents()
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
            try reloadEvents()
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

    func updateNote(for detail: EventDetail, note: String) {
        guard let id = detail.event.id else { return }
        do {
            try store?.updateNote(eventID: id, note: note)
            try reloadEvents()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func delete(_ detail: EventDetail) {
        guard let id = detail.event.id else { return }
        do {
            try store?.deleteEvent(eventID: id)
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
            statusMessage = "Imported \(result.events.count) events"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

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
}
