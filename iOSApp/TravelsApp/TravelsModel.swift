// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import LocalAuthentication
import Photos
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
    @Published private(set) var detectedTrips: [DetectedTrip] = []
    @Published private(set) var selectedMapDisplay: MapDisplaySelection = .all
    @Published var statusMessage: String?
    @Published var searchResults: [EventDetail] = []
    @Published var addressResolutionLog: [String] = []
    @Published var addressResolutionStatus = "Idle"
    @Published var addressResolutionPendingCount = 0
    @Published var addressResolutionLastRunAt: Date?
    @Published var addressResolutionLastSuccessAt: Date?
    @Published var addressResolutionLastError: String?
    @Published var addressResolutionCurrentTarget: String?
    @Published var locationAuthorizationMessage: String?
    var mapVisibleEventIDs: [Int64] = []
    var listVisibleEventIDs: [Int64] = []
    @Published var listScrollTargetEventID: Int64?
    @Published var listScrollCommandID = UUID()
    @Published var mapFocusEventIDs: [Int64]?
    @Published var mapCameraCommandID = UUID()
    @Published var mapCameraRegion: MKCoordinateRegion?
    @Published private(set) var dateSelectionLowerBound = Calendar.current.startOfDay(for: Date())
    @Published private(set) var dateSelectionUpperBound = Calendar.current.startOfDay(for: Date())

    private var store: TravelsStore?
    private var storeURL: URL?
    private var settingsStore: SettingsStore?
    private let locationService = LocationTrackingService()
    private let tripDetectionService = TripDetectionService()
    private var appSupportURL: URL?
    private var addressResolutionTask: Task<Void, Never>?
    private var addressResolutionTimerTask: Task<Void, Never>?
    private var addressResolutionNeedsRerun = false

    func bootstrap() async {
        do {
            let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            let appSupport = urls[0].appendingPathComponent("Travels", isDirectory: true)
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: appSupport.appendingPathComponent("Photos", isDirectory: true),
                withIntermediateDirectories: true
            )
            appSupportURL = appSupport
            let storeURL = appSupport.appendingPathComponent("Travels.sqlite")
            let launch = try openOrRepairStore(storeURL: storeURL)
            self.store = launch.store
            self.storeURL = storeURL
            self.settingsStore = SettingsStore(store: launch.store)
            self.settings = try settingsStore?.load() ?? AppSettings()
            self.isListView = settings.preferListView
            locationService.onStatusMessage = { [weak self] message in
                self?.statusMessage = message
            }
            locationService.onAuthorizationStateChanged = { [weak self] message in
                guard let self else { return }
                self.locationAuthorizationMessage = message
            }
            locationService.onTrackedEvent = { [weak self] in
                guard let self else { return }
                Task(priority: .utility) { [weak self] in
                    guard let self else { return }
                    await Task.yield()
                    await MainActor.run {
                        do {
                            try self.reloadEvents()
                        } catch {
                            self.statusMessage = error.localizedDescription
                        }
                    }
                }
            }
            locationService.onManualTrackedEvent = { [weak self] eventID, timestamp in
                guard let self else { return }
                focusAfterCapture(eventID: eventID, timestamp: timestamp)
            }
            if let repairMessage = launch.repairMessage {
                self.statusMessage = repairMessage
            }
            let latestAcceptedEvent = try launch.store.latestEvent(includeDemo: settings.includeDemoData)
            locationService.configure(
                store: launch.store,
                settings: settings,
                latestEvent: latestAcceptedEvent
            )
            let didRepairDatabase = launch.repairMessage != nil
            Task(priority: .userInitiated) { [weak self, launch, settings, didRepairDatabase] in
                do {
                    guard let self else { return }
                    if settings.includeDemoData && !didRepairDatabase {
                        try self.ensureDemoReferenceDate(referenceDate: Date())
                        try self.seedDemoDataIfNeeded()
                    }
                    let startup = try loadStartupState(store: launch.store, settings: settings)
                    await MainActor.run {
                        self.selectedDate = startup.selectedDate
                        self.events = startup.events
                        self.refreshDetectedTrips()
                        self.locationService.configure(
                            store: launch.store,
                            settings: settings,
                            latestEvent: try? launch.store.latestEvent(includeDemo: settings.includeDemoData)
                        )
                        self.refreshDateSelectionBounds()
                        self.startAddressResolutionTimer()
                        if settings.requireAuthentication {
                            self.isUnlocked = false
                            self.authenticate()
                        }
                    }
                } catch {
                    await MainActor.run {
                        self?.statusMessage = error.localizedDescription
                    }
                }
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func reloadEvents() throws {
        guard let store else { return }
        events = try store.events(
            on: selectedDate,
            includePreviousDayContext: shouldIncludePreviousDayContext(store: store, settings: settings, date: selectedDate),
            includeDemo: settings.includeDemoData
        )
        refreshDetectedTrips()
        refreshDateSelectionBounds()
        refreshSelectedEventIfNeeded()
    }

    func selectDate(_ date: Date) {
        selectedDate = Calendar.current.startOfDay(for: date)
        do {
            try reloadEvents()
            mapVisibleEventIDs = []
            listVisibleEventIDs = []
            listScrollTargetEventID = nil
            mapFocusEventIDs = nil
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
        searchPlaceOptions(matching: SearchCriteria())
    }

    func searchPlaceOptions(matching criteria: SearchCriteria) -> SearchPlaceOptions {
        do {
            let baseCriteria = SearchCriteria(
                term: criteria.term,
                startDate: criteria.startDate,
                endDate: criteria.endDate,
                hasNote: criteria.hasNote,
                source: criteria.source
            )
            let countryDetails = try searchDetails(matching: baseCriteria)
            let countryOptions = uniquePlaceValues(countryDetails.compactMap { nonEmpty($0.geolocation?.country) })

            let selectedCountry = validatedPlaceSelection(criteria.country, in: countryOptions)
            let administrativeCriteria = baseCriteria.with(country: selectedCountry)
            let administrativeDetails = try searchDetails(matching: administrativeCriteria)
            let administrativeOptions = uniquePlaceValues(administrativeDetails.compactMap { nonEmpty($0.geolocation?.administrativeArea) })

            let selectedAdministrativeArea = validatedPlaceSelection(criteria.administrativeArea, in: administrativeOptions)
            let subAdministrativeCriteria = administrativeCriteria.with(administrativeArea: selectedAdministrativeArea)
            let subAdministrativeDetails = try searchDetails(matching: subAdministrativeCriteria)
            let subAdministrativeOptions = uniquePlaceValues(subAdministrativeDetails.compactMap { nonEmpty($0.geolocation?.subAdministrativeArea) })

            let selectedSubAdministrativeArea = validatedPlaceSelection(criteria.subAdministrativeArea, in: subAdministrativeOptions)
            let localityCriteria = subAdministrativeCriteria.with(subAdministrativeArea: selectedSubAdministrativeArea)
            let localityDetails = try searchDetails(matching: localityCriteria)
            let localityOptions = uniquePlaceValues(localityDetails.compactMap { nonEmpty($0.geolocation?.locality) })

            let selectedLocality = validatedPlaceSelection(criteria.locality, in: localityOptions)
            let bodyOfWaterCriteria = localityCriteria.with(locality: selectedLocality, bodyOfWater: nil)
            let bodyOfWaterDetails = try searchDetails(matching: bodyOfWaterCriteria)
            let bodyOfWaterOptions = uniquePlaceValues(bodyOfWaterDetails.compactMap {
                nonEmpty($0.geolocation?.inlandWater) ?? nonEmpty($0.geolocation?.ocean)
            })
            _ = validatedPlaceSelection(criteria.bodyOfWater, in: bodyOfWaterOptions)

            return SearchPlaceOptions(
                countries: countryOptions,
                administrativeAreas: administrativeOptions,
                subAdministrativeAreas: subAdministrativeOptions,
                localities: localityOptions,
                bodyOfWaters: bodyOfWaterOptions
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

    func aboutStatistics() -> AboutStatistics {
        do {
            let details = try store?.allEvents(includeDemo: settings.includeDemoData) ?? []
            let uniqueLocations = Set(details.compactMap { $0.geolocation?.id }).count
            let unaddressedLocations = details.filter { detail in
                guard let geolocation = detail.geolocation else { return true }
                return geolocation.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }.count
            return AboutStatistics(
                totalLocations: details.count,
                uniqueLocations: uniqueLocations,
                unaddressedLocations: unaddressedLocations
            )
        } catch {
            statusMessage = error.localizedDescription
            return .empty
        }
    }

    func updateMapVisibleEventIDs(_ eventIDs: [Int64]) {
        guard mapVisibleEventIDs != eventIDs else { return }
        mapVisibleEventIDs = eventIDs
    }

    func updateMapCameraRegion(_ region: MKCoordinateRegion?) {
        guard !regionsApproximatelyEqual(mapCameraRegion, region) else { return }
        mapCameraRegion = region
    }

    func updateListVisibleEventIDs(_ eventIDs: [Int64]) {
        guard listVisibleEventIDs != eventIDs else { return }
        listVisibleEventIDs = eventIDs
    }

    func prepareMapFocusFromList() {
        mapFocusEventIDs = listVisibleEventIDs
        mapCameraCommandID = UUID()
    }

    func prepareListScrollTargetFromMap() {
        let visibleIDs = currentMapVisibleEventIDs()
        requestListScrollTarget(visibleIDs.first ?? mapVisibleEventIDs.first ?? events.first?.id)
    }

    func resetMapZoomToFullDay() {
        mapFocusEventIDs = nil
        mapCameraCommandID = UUID()
    }

    func panMapToMostRecentEvent() {
        guard let lastEventID = events.last?.id else { return }
        mapFocusEventIDs = [lastEventID]
        mapCameraCommandID = UUID()
    }

    func scrollListToTop() {
        requestListScrollTarget(events.first?.id)
    }

    func scrollListToBottom() {
        requestListScrollTarget(events.last?.id)
    }

    func addCurrentLocation(forceStopped: Bool = false) {
        locationService.requestCurrentLocation(forceStopped: forceStopped)
    }

    func selectAllMapDisplay() {
        selectedMapDisplay = .all
        mapFocusEventIDs = nil
        listScrollTargetEventID = nil
        if !isListView {
            mapCameraCommandID = UUID()
        }
        refreshSelectedEventIfNeeded()
    }

    func selectStoppedOnlyMapDisplay() {
        selectedMapDisplay = .stoppedOnly
        mapFocusEventIDs = nil
        listScrollTargetEventID = nil
        if !isListView {
            mapCameraCommandID = UUID()
        }
        refreshSelectedEventIfNeeded()
    }

    func isAllMapDisplaySelected() -> Bool {
        if case .all = selectedMapDisplay { return true }
        return false
    }

    func isStoppedOnlyMapDisplaySelected() -> Bool {
        if case .stoppedOnly = selectedMapDisplay { return true }
        return false
    }

    func isTripMapDisplaySelected(_ tripID: DetectedTrip.ID) -> Bool {
        guard case .trips(let tripIDs) = selectedMapDisplay else { return false }
        return tripIDs.contains(tripID)
    }

    func toggleTripDisplay(_ tripID: DetectedTrip.ID) {
        switch selectedMapDisplay {
        case .all, .stoppedOnly:
            selectedMapDisplay = .trips([tripID])
        case .trips(var tripIDs):
            if tripIDs.contains(tripID) {
                tripIDs.remove(tripID)
                selectedMapDisplay = tripIDs.isEmpty ? .all : .trips(tripIDs)
            } else {
                tripIDs.insert(tripID)
                selectedMapDisplay = .trips(tripIDs)
            }
        }

        if case .trips(let tripIDs) = selectedMapDisplay, !tripIDs.isEmpty {
            focusSelectedTrips(tripIDs)
        } else {
            clearTripFocus()
        }
        refreshSelectedEventIfNeeded()
    }

    func rebuildSolarPeriodCalculations(timeZoneIdentifier: String) {
        guard let store else {
            statusMessage = TravelsError.databaseOpenFailed("Database is unavailable.").localizedDescription
            return
        }
        Task(priority: .utility) { [weak self] in
            do {
                let processedCount = try store.rebuildSolarPeriodCalculations(timeZoneIdentifier: timeZoneIdentifier)
                await MainActor.run {
                    guard let self else { return }
                    self.statusMessage = "Recalculated solar periods for \(processedCount) events."
                    do {
                        try self.reloadEvents()
                    } catch {
                        self.statusMessage = error.localizedDescription
                    }
                }
            } catch {
                await MainActor.run {
                    self?.statusMessage = error.localizedDescription
                }
            }
        }
    }

    func rebuildTwilightCalculations(timeZoneIdentifier: String) {
        rebuildSolarPeriodCalculations(timeZoneIdentifier: timeZoneIdentifier)
    }

    var canAddCurrentLocation: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    var hasStoppedLocations: Bool {
        events.contains(where: { isStoppedLocationEvent($0.event) })
    }

    func requestListScrollTarget(_ eventID: Int64?) {
        listScrollTargetEventID = eventID
        listScrollCommandID = UUID()
    }

    func dateSelectionRange() -> ClosedRange<Date> {
        dateSelectionLowerBound...dateSelectionUpperBound
    }

    func clampedDateSelection(_ date: Date) -> Date {
        let range = dateSelectionRange()
        return min(max(Calendar.current.startOfDay(for: date), range.lowerBound), range.upperBound)
    }

    var displayedEvents: [EventDetail] {
        filteredEvents(from: events, selection: selectedMapDisplay, detectedTrips: detectedTrips)
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
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let result = try GPXImporter.parse(url: url)
            var importedEventIDs: [Int64] = []
            importedEventIDs.reserveCapacity(result.events.count)
            for event in result.events {
                let eventID = try store.saveEvent(event)
                importedEventIDs.append(eventID)
            }
            if let firstImported = result.events.first, importedEventIDs.first != nil {
                focusAfterImport(eventIDs: importedEventIDs, timestamp: firstImported.timestamp)
            } else {
                try reloadEvents()
            }
            statusMessage = "Imported \(result.events.count) events"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func importPhoto(assetIdentifier: String?, data: Data, note: String = "") throws -> ImportedPhotoImportResult {
        do {
            guard let store, let photoURL = makePhotoURL() else {
                throw TravelsError.photoImportFailed("Unable to prepare photo storage.")
            }
            guard let assetIdentifier, !assetIdentifier.isEmpty else {
                throw TravelsError.photoImportFailed("Unable to retrieve photo metadata.")
            }
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
            guard let asset = assets.firstObject else {
                throw TravelsError.photoImportFailed("Unable to retrieve photo metadata.")
            }
            guard let assetDate = asset.creationDate else {
                throw TravelsError.photoImportFailed("Unable to retrieve timestamp from image.")
            }
            guard let assetLocation = asset.location else {
                throw TravelsError.photoImportFailed("Unable to retrieve location information from image.")
            }

            try data.write(to: photoURL, options: [.atomic])
            let location = CLLocation(
                coordinate: assetLocation.coordinate,
                altitude: assetLocation.altitude,
                horizontalAccuracy: assetLocation.horizontalAccuracy,
                verticalAccuracy: assetLocation.verticalAccuracy,
                course: assetLocation.course,
                speed: assetLocation.speed,
                timestamp: assetDate
            )
            let event = LocationEvent(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                horizontalAccuracy: location.horizontalAccuracy,
                verticalAccuracy: location.verticalAccuracy,
                altitude: location.altitude,
                course: location.course,
                speed: location.speed,
                timestamp: assetDate,
                localizedDate: TravelsDateTools.localizedDayString(for: assetDate, timeZoneIdentifier: nil),
                source: .photo,
                note: note,
                externalReference: asset.localIdentifier,
                photoFilename: photoURL.lastPathComponent
            )
            let eventID = try store.saveEvent(event)
            try reloadEvents()
            statusMessage = "Imported photo"
            return ImportedPhotoImportResult(eventID: eventID, timestamp: assetDate)
        } catch {
            throw error
        }
    }

    func focusAfterImport(eventID: Int64, timestamp: Date) {
        focusAfterEventIDs([eventID], timestamp: timestamp)
    }

    func focusAfterImport(eventIDs: [Int64], timestamp: Date) {
        focusAfterEventIDs(eventIDs, timestamp: timestamp)
    }

    func focusAfterCapture(eventID: Int64, timestamp: Date) {
        focusAfterEventIDs([eventID], timestamp: timestamp)
    }

    private func focusAfterEventIDs(_ eventIDs: [Int64], timestamp: Date) {
        selectDate(timestamp)
        let distinctEventIDs = eventIDs.reduce(into: [Int64]()) { partialResult, eventID in
            guard !partialResult.contains(eventID) else { return }
            partialResult.append(eventID)
        }
        requestListScrollTarget(distinctEventIDs.first)
        mapFocusEventIDs = distinctEventIDs.isEmpty ? nil : distinctEventIDs
        mapCameraCommandID = UUID()
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
                includePreviousDayContext: shouldIncludePreviousDayContext(store: store, settings: settings, date: selectedDate),
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

    func createDatabaseBackup() throws -> URL {
        guard let store, let storeURL else {
            throw TravelsError.databaseOpenFailed("Database is unavailable.")
        }
        try store.checkpoint()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "Travels-backup-\(formatter.string(from: Date())).sqlite"
        let backupURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try FileManager.default.removeItem(at: backupURL)
        }
        try FileManager.default.copyItem(at: storeURL, to: backupURL)
        return backupURL
    }

    func restoreDatabase(from sourceURL: URL) throws {
        guard let storeURL else {
            throw TravelsError.databaseOpenFailed("Database is unavailable.")
        }
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        try store?.checkpoint()
        locationService.stop()
        store = nil
        settingsStore = nil
        if FileManager.default.fileExists(atPath: storeURL.path) {
            try FileManager.default.removeItem(at: storeURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: storeURL)
        let restoredStore = try TravelsStore(url: storeURL)
        store = restoredStore
        settingsStore = SettingsStore(store: restoredStore)
        settings = try settingsStore?.load() ?? AppSettings()
        isListView = settings.preferListView
        if let latest = try restoredStore.latestEventDate(includeDemo: settings.includeDemoData) {
            selectedDate = Calendar.current.startOfDay(for: latest)
        } else {
            selectedDate = Calendar.current.startOfDay(for: Date())
        }
        try reloadEvents()
        locationService.configure(store: restoredStore, settings: settings, latestEvent: try restoredStore.latestEvent(includeDemo: settings.includeDemoData))
        refreshDateSelectionBounds()
    }

#if DEBUG
    func rerunAddressResolutionQueue() {
        requestAddressResolution(maxBatchSize: nil)
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
        let referenceDate = try demoReferenceDate()
        let storedSeedVersion = try store.setting("demo.seed.version")
        if storedSeedVersion != DemoData.seedVersion {
            try syncDemoMetadata(referenceDate: referenceDate)
            try store.setSetting("demo.seed.version", value: DemoData.seedVersion)
        }
        guard try store.eventCount(includeDemo: false) == 0 else { return }
        guard try store.eventCount(includeDemo: true) == 0 else { return }
        try DemoData.seed(into: store, anchoredTo: referenceDate)
        try store.setSetting("demo.seed.version", value: DemoData.seedVersion)
    }

    private func syncDemoMetadata(referenceDate: Date) throws {
        guard let store else { return }
        let demoPoints = try DemoData.trackPoints(anchoredTo: referenceDate)
        for point in demoPoints {
            guard let existing = try store.findDuplicate(point.event) else { continue }
            guard existing.geolocationID == nil, let geolocation = point.geolocation else { continue }
            let geolocationID = try store.saveGeolocation(geolocation)
            guard let eventID = existing.id else { continue }
            try store.attachGeolocation(geolocationID, toEvent: eventID)
        }
    }

    private func focusOnDemoDataIfNeeded() throws {
        guard let store else { return }
        guard settings.includeDemoData else { return }
        guard try store.eventCount(includeDemo: false) == 0 else { return }
        guard let latestVisibleDate = try store.latestEventDate(includeDemo: true) else { return }
        selectedDate = Calendar.current.startOfDay(for: latestVisibleDate)
        try reloadEvents()
    }

    private func refreshDateSelectionBounds() {
        guard let store else { return }
        let includeDemo = settings.includeDemoData
        Task(priority: .utility) { [weak self, store] in
            do {
                let range = try store.eventDateRange(includeDemo: includeDemo)
                let today = Calendar.current.startOfDay(for: Date())
                let lowerBound = Calendar.current.startOfDay(for: range.oldest ?? today)
                let latestBound = max(Calendar.current.startOfDay(for: range.latest ?? today), lowerBound)
                let upperBound = max(latestBound, today)
                await MainActor.run {
                    self?.dateSelectionLowerBound = lowerBound
                    self?.dateSelectionUpperBound = upperBound
                }
            } catch {
                await MainActor.run {
                    self?.dateSelectionLowerBound = Calendar.current.startOfDay(for: Date())
                    self?.dateSelectionUpperBound = Calendar.current.startOfDay(for: Date())
                    self?.statusMessage = error.localizedDescription
                }
            }
        }
    }

    private func startAddressResolutionTimer() {
        addressResolutionTimerTask?.cancel()
        addressResolutionTimerTask = Task(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                guard !Task.isCancelled else { break }
                await MainActor.run { [weak self] in
                    self?.requestAddressResolution()
                }
            }
        }
    }

    private func requestAddressResolution(maxBatchSize: Int? = 1) {
        guard settings.resolveAddresses || settings.resolveMissingAddresses else { return }
        addressResolutionNeedsRerun = true
        addressResolutionStatus = "Queued"
        appendAddressResolutionLog("Queued address resolution")
        guard addressResolutionTask == nil else { return }
        let store = self.store
        let includeDemoData = settings.includeDemoData
        let resolveAddresses = settings.resolveAddresses
        let resolveMissingAddresses = settings.resolveMissingAddresses
        addressResolutionTask = Task(priority: .utility) { [weak self, store, includeDemoData, resolveAddresses, resolveMissingAddresses, maxBatchSize] in
            defer {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.addressResolutionTask = nil
                    self.addressResolutionStatus = "Idle"
                    self.addressResolutionCurrentTarget = nil
                    self.addressResolutionPendingCount = 0
                }
            }

            repeat {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.addressResolutionNeedsRerun = false
                    self.addressResolutionStatus = "Running"
                    self.addressResolutionLastRunAt = Date()
                }

                guard let store, resolveAddresses || resolveMissingAddresses else { return }

                do {
                    var resolvedCount = 0
                    var processedEventIDs = Set<Int64>()
                    var processedThisRun = 0
                    let batchLimit = maxBatchSize ?? .max
                    while true {
                        guard processedThisRun < batchLimit else {
                            break
                        }
                        let unresolved = try store.eventsNeedingGeolocation(includeDemo: includeDemoData)
                            .sorted { $0.event.timestamp > $1.event.timestamp }
                            .filter { detail in
                                guard let id = detail.event.id else { return true }
                                return !processedEventIDs.contains(id)
                            }

                        await MainActor.run { [weak self] in
                            self?.addressResolutionPendingCount = unresolved.count
                        }

                        guard let detail = unresolved.first, let eventID = detail.event.id else {
                            break
                        }

                        let currentTarget = {
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateStyle = .short
                            dateFormatter.timeStyle = .short
                            return "Event \(detail.event.id ?? 0) @ \(dateFormatter.string(from: detail.event.timestamp))"
                        }()

                        await MainActor.run { [weak self] in
                            guard let self else { return }
                            self.addressResolutionCurrentTarget = currentTarget
                            self.appendAddressResolutionLog("Resolving \(currentTarget)")
                        }

                        let location = CLLocation(
                            latitude: detail.event.latitude,
                            longitude: detail.event.longitude
                        )
                        let result = await ReverseGeocodingService.shared.lookup(for: location, store: store)
                        let waited = result.waitedSeconds > 0 ? String(format: "%.1fs", result.waitedSeconds) : "no wait"
                        let outcome = result.geolocation == nil ? "unresolved" : "resolved"
                        await MainActor.run { [weak self] in
                            guard let self else { return }
                            self.appendAddressResolutionLog("\(currentTarget): \(outcome) via \(result.source.rawValue), \(waited) - \(result.summary)")
                            if let errorDescription = result.errorDescription {
                                self.addressResolutionLastError = errorDescription
                            }
                        }

                        guard let geolocation = result.geolocation else {
                            processedEventIDs.insert(eventID)
                            continue
                        }

                        processedEventIDs.insert(eventID)
                        if let geolocationID = geolocation.id {
                            try store.attachGeolocation(geolocationID, toEvent: eventID)
                            resolvedCount += 1
                            processedThisRun += 1
                            await MainActor.run { [weak self] in
                                self?.addressResolutionLastSuccessAt = Date()
                                self?.addressResolutionLastError = nil
                            }
                        } else {
                            processedThisRun += 1
                        }
                    }

                    if resolvedCount > 0 {
                        await MainActor.run { [weak self] in
                            guard let self else { return }
                            do {
                                try self.reloadEvents()
                            } catch {
                                self.statusMessage = error.localizedDescription
                            }
                        }
                    }
                } catch {
                    await MainActor.run { [weak self] in
                        self?.addressResolutionLastError = error.localizedDescription
                        self?.statusMessage = error.localizedDescription
                    }
                    await MainActor.run { [weak self] in
                        self?.appendAddressResolutionLog("Queue failed: \(error.localizedDescription)")
                    }
                }

                let shouldRepeat = await MainActor.run { [weak self] in
                    self?.addressResolutionNeedsRerun ?? false
                }
                if !shouldRepeat {
                    break
                }
            } while true
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

    private func validatedPlaceSelection(_ value: String?, in options: [String]) -> String? {
        guard let value else { return nil }
        return options.contains(value) ? value : nil
    }

    private func searchDetails(matching criteria: SearchCriteria) throws -> [EventDetail] {
        try store?.search(criteria, includeDemo: settings.includeDemoData) ?? []
    }

    private func refreshSelectedEventIfNeeded() {
        guard let selectedEvent, let id = selectedEvent.id else { return }
        self.selectedEvent = displayedEvents.first(where: { $0.id == id }) ?? nil
    }

    private func focusSelectedTrips(_ tripIDs: Set<DetectedTrip.ID>) {
        let selectedTrips = detectedTrips.filter { tripIDs.contains($0.id) }
        guard !selectedTrips.isEmpty else {
            clearTripFocus()
            return
        }

        let tripEventIDs = selectedTrips.reduce(into: Set<Int64>()) { partialResult, trip in
            partialResult.formUnion(trip.displayEventIDs.compactMap { $0 })
        }
        guard !tripEventIDs.isEmpty else {
            clearTripFocus()
            return
        }

        let tripEvents = events.filter { detail in
            guard let id = detail.id else { return false }
            return tripEventIDs.contains(id)
        }.sorted { $0.event.timestamp < $1.event.timestamp }

        guard let firstEvent = tripEvents.first, let firstEventID = firstEvent.id else {
            clearTripFocus()
            return
        }

        if isListView {
            requestListScrollTarget(firstEventID)
        } else {
            mapFocusEventIDs = tripEvents.compactMap(\.id)
            mapCameraCommandID = UUID()
        }
    }

    private func clearTripFocus() {
        mapFocusEventIDs = nil
        if !isListView {
            mapCameraCommandID = UUID()
        }
    }

    private func refreshDetectedTrips() {
        let trips = tripDetectionService.detectTrips(
            from: events.map(\.event),
            timeZone: tripDisplayTimeZone(for: events)
        )
        detectedTrips = trips
        switch selectedMapDisplay {
        case .all, .stoppedOnly:
            clearTripFocus()
            break
        case .trips(let tripIDs):
            let validIDs = Set(trips.map(\.id)).intersection(tripIDs)
            if validIDs.isEmpty {
                selectedMapDisplay = .all
                clearTripFocus()
            } else if validIDs != tripIDs {
                selectedMapDisplay = .trips(validIDs)
                focusSelectedTrips(validIDs)
            }
        }
    }

    private func tripDisplayTimeZone(for events: [EventDetail]) -> TimeZone {
        for detail in events {
            if let identifier = detail.geolocation?.timeZoneIdentifier,
               let timeZone = TimeZone(identifier: identifier) {
                return timeZone
            }
        }
        return .current
    }

    private func currentMapVisibleEventIDs() -> [Int64] {
        mapVisibleEventIDs(in: mapCameraRegion)
    }

    private func mapVisibleEventIDs(in region: MKCoordinateRegion?) -> [Int64] {
        guard let region else { return mapVisibleEventIDs }
        return events.compactMap { detail -> Int64? in
            guard let id = detail.id else { return nil }
            guard isCoordinate(detail.coordinate, inside: region) else { return nil }
            return id
        }
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

    private func regionsApproximatelyEqual(_ lhs: MKCoordinateRegion?, _ rhs: MKCoordinateRegion?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            let centerDelta = abs(lhs.center.latitude - rhs.center.latitude)
                + abs(lhs.center.longitude - rhs.center.longitude)
            let spanDelta = abs(lhs.span.latitudeDelta - rhs.span.latitudeDelta)
                + abs(lhs.span.longitudeDelta - rhs.span.longitudeDelta)
            return centerDelta < 0.000001 && spanDelta < 0.000001
        default:
            return false
        }
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

struct AboutStatistics: Equatable {
    var totalLocations: Int
    var uniqueLocations: Int
    var unaddressedLocations: Int

    static let empty = AboutStatistics(totalLocations: 0, uniqueLocations: 0, unaddressedLocations: 0)
}

private struct StartupState {
    let selectedDate: Date
    let events: [EventDetail]
}

private struct StoreLaunchResult: Sendable {
    let store: TravelsStore
    let repairMessage: String?
}

struct ImportedPhotoImportResult {
    let eventID: Int64
    let timestamp: Date
}

private func loadStartupState(store: TravelsStore, settings: AppSettings) throws -> StartupState {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let selectedDate: Date
    if settings.includeDemoData,
       try store.eventCount(includeDemo: false) == 0,
       let latestVisibleDate = try store.latestEventDate(includeDemo: true) {
        selectedDate = calendar.startOfDay(for: latestVisibleDate)
    } else {
        selectedDate = today
    }
    let includePreviousDayContext = shouldIncludePreviousDayContext(store: store, settings: settings, date: selectedDate)
    let events = try store.events(
        on: selectedDate,
        includePreviousDayContext: includePreviousDayContext,
        includeDemo: settings.includeDemoData
    )
    return StartupState(selectedDate: selectedDate, events: events)
}

private func shouldIncludePreviousDayContext(store: TravelsStore, settings: AppSettings, date: Date) -> Bool {
    guard settings.includePreviousDayContext else { return false }

    let previousDate = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
    do {
        guard let previousTail = try store.events(
            on: previousDate,
            includePreviousDayContext: false,
            includeDemo: true
        ).last else {
            return false
        }
        return !previousTail.event.isDemo
    } catch {
        return false
    }
}

private func openOrRepairStore(storeURL: URL) throws -> StoreLaunchResult {
    do {
        let store = try TravelsStore(url: storeURL)
        if let outcome = try store.validateAndRepairIfNeeded() {
            return StoreLaunchResult(store: store, repairMessage: outcome.userFacingMessage)
        }
        return StoreLaunchResult(store: store, repairMessage: nil)
    } catch {
        let quarantineDirectory = try TravelsStore.quarantineDatabaseFiles(at: storeURL)
        let store = try TravelsStore(url: storeURL)
        return StoreLaunchResult(
            store: store,
            repairMessage: "Travels found a database problem and rebuilt a fresh database. A backup was saved in \(quarantineDirectory.lastPathComponent)."
        )
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

private extension SearchCriteria {
    func with(
        country: String? = nil,
        administrativeArea: String? = nil,
        subAdministrativeArea: String? = nil,
        locality: String? = nil,
        bodyOfWater: String? = nil
    ) -> SearchCriteria {
        SearchCriteria(
            term: term,
            startDate: startDate,
            endDate: endDate,
            hasNote: hasNote,
            country: country ?? self.country,
            administrativeArea: administrativeArea ?? self.administrativeArea,
            subAdministrativeArea: subAdministrativeArea ?? self.subAdministrativeArea,
            locality: locality ?? self.locality,
            bodyOfWater: bodyOfWater ?? self.bodyOfWater,
            source: source
        )
    }
}
