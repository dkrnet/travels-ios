// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.

import MapKit
import SwiftUI
import UniformTypeIdentifiers

#if canImport(TravelsCore)
import TravelsCore
#endif

struct ContentView: View {
    @EnvironmentObject private var model: TravelsModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingAbout = false
    @State private var showingSettings = false
    @State private var showingSearch = false
    @State private var showingDatePicker = false
    @State private var showingImporter = false
    @State private var showingPhotoImporter = false
    @State private var showingDeveloperDiagnostics = false
    @State private var shareItem: ShareItem?
    @State private var datePickerSelection = Date()
    @State private var mapQuickActionShowsLatest = true
    @State private var listQuickActionShowsTop = false

    var body: some View {
        NavigationStack {
            ZStack {
                Group {
                    if model.isListView {
                        EventListView(events: model.displayedEvents)
                            .id(model.selectedDate)
                    } else {
                        EventMapView(day: model.selectedDate, events: model.displayedEvents)
                            .id(model.selectedDate)
                    }
                }
                .blur(radius: model.isUnlocked ? 0 : 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if model.isHighPrecisionLocationActive {
                    VStack {
                        LocationPrecisionStatusBadge()
                            .padding(.top, 8)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .allowsHitTesting(false)
                }

                if let message = model.locationAuthorizationMessage, model.isUnlocked {
                    VStack {
                        PermissionBanner(message: message)
                            .padding(.top, 12)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .allowsHitTesting(false)
                }

                if !model.isUnlocked {
                    LockedView()
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        model.selectDate(Calendar.current.date(byAdding: .day, value: -1, to: model.selectedDate) ?? model.selectedDate)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(Calendar.current.startOfDay(for: model.selectedDate) <= model.dateSelectionRange().lowerBound)
                    Button {
                        datePickerSelection = model.clampedDateSelection(model.selectedDate)
                        showingDatePicker = true
                    } label: {
                        Image(systemName: "calendar")
                    }
                    Button {
                        model.selectDate(Calendar.current.date(byAdding: .day, value: 1, to: model.selectedDate) ?? model.selectedDate)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(Calendar.current.startOfDay(for: model.selectedDate) >= model.dateSelectionRange().upperBound)
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        if model.isListView {
                            model.prepareMapFocusFromList()
                        } else {
                            model.prepareListScrollTargetFromMap()
                        }
                        model.isListView.toggle()
                        model.saveSettings()
                    } label: {
                        Image(systemName: model.isListView ? "map" : "list.bullet")
                    }
                    Button {
                        if model.isListView {
                            if listQuickActionShowsTop {
                                model.scrollListToTop()
                            } else {
                                model.scrollListToBottom()
                            }
                            listQuickActionShowsTop.toggle()
                        } else {
                            if mapQuickActionShowsLatest {
                                model.panMapToMostRecentEvent()
                            } else {
                                model.resetMapZoomToFullDay()
                            }
                            mapQuickActionShowsLatest.toggle()
                        }
                    } label: {
                        Image(systemName: model.isListView
                              ? (listQuickActionShowsTop ? "arrow.up.to.line.compact" : "arrow.down.to.line.compact")
                              : (mapQuickActionShowsLatest ? "location.fill" : "arrow.up.left.and.arrow.down.right"))
                    }
                    .disabled(model.events.isEmpty)
                    Menu {
                        Button("About") { showingAbout = true }
                        Button("Import Location File") { showingImporter = true }
                        Button("Import Photo") { showingPhotoImporter = true }
                        Button("Export Location File") {
                            if let url = model.exportDisplayedGPX() {
                                shareItem = ShareItem(url: url)
                            }
                        }
#if DEBUG
                        Button("Developer Diagnostics") {
                            showingDeveloperDiagnostics = true
                        }
#endif
                        Button("Settings") { showingSettings = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }

                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        showingSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .disabled(!model.isUnlocked)

                    Menu {
                        // REGRESSION GUARD: keep these rows as standard Toggle controls so the selection state is rendered consistently across device sizes and does not regress to a custom checkmark layout.
                        displaySelectionToggle("All", isOn: Binding(
                            get: { model.isAllMapDisplaySelected() },
                            set: { isOn in
                                if isOn {
                                    model.selectAllMapDisplay()
                                }
                            }
                        ))
                        displaySelectionToggle(
                            "Stopped Only",
                            isOn: Binding(
                                get: { model.isStoppedOnlyMapDisplaySelected() },
                                set: { isOn in
                                    if isOn {
                                        model.selectStoppedOnlyMapDisplay()
                                    } else {
                                        model.selectAllMapDisplay()
                                    }
                                }
                            ),
                            isEnabled: model.hasStoppedLocations
                        )

                        if !model.detectedTrips.isEmpty {
                            // REGRESSION GUARD: the menu renders trip rows in the opposite visual order of the detector output, so reverse here to keep earlier trips higher in the list.
                            ForEach(Array(model.detectedTrips.reversed()), id: \.id) { trip in
                                displaySelectionToggle(trip.displayName, isOn: Binding(
                                    get: { model.isTripMapDisplaySelected(trip.id) },
                                    set: { isOn in
                                        if isOn != model.isTripMapDisplaySelected(trip.id) {
                                            model.toggleTripDisplay(trip.id)
                                        }
                                    }
                                ))
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.branch")
                    }
                    .disabled(!model.isUnlocked)

                    Menu {
                        Button("Add Current Location") {
                            model.addCurrentLocation()
                        }
                        Button("Force Add Stopped Location") {
                            model.addCurrentLocation(forceStopped: true)
                        }
                    } label: {
                        Image(systemName: "plus")
                            // REGRESSION GUARD: keep the add button visibly muted when it is disabled so the inactive state is obvious and the disabled affordance does not regress.
                            .foregroundStyle(model.canAddCurrentLocation ? .primary : .tertiary)
                    } primaryAction: {
                        model.addCurrentLocation()
                    }
                    .disabled(!model.canAddCurrentLocation)
                }
            }
            .sheet(item: $model.selectedEvent) { detail in
                EventDetailView(detail: detail)
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingSearch) {
                SearchView(initialCriteria: model.lastSearchCriteria)
            }
            .sheet(isPresented: $showingDatePicker) {
                DatePickerSheet(
                    selection: $datePickerSelection,
                    range: model.dateSelectionRange(),
                    onCancel: {
                        showingDatePicker = false
                    },
                    onDone: {
                        model.selectDate(datePickerSelection)
                        showingDatePicker = false
                    }
                )
            }
            .sheet(isPresented: $showingPhotoImporter) {
                PhotoImportView()
            }
#if DEBUG
            .sheet(isPresented: $showingDeveloperDiagnostics) {
                DeveloperDiagnosticsView()
            }
#endif
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.url])
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    model.importGPX(url: url)
                }
            }
            .alert("Travels", isPresented: Binding(get: { model.statusMessage != nil }, set: { if !$0 { model.statusMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.statusMessage ?? "")
            }
            .onChange(of: model.selectedDate) { _, _ in
                mapQuickActionShowsLatest = true
                listQuickActionShowsTop = false
            }
            .onChange(of: model.isListView) { _, _ in
                mapQuickActionShowsLatest = true
                if model.isListView {
                    listQuickActionShowsTop = false
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard model.settings.requireAuthentication else { return }
                switch newPhase {
                case .active:
                    if !model.isUnlocked {
                        model.authenticate()
                    }
                case .inactive, .background:
                    model.isUnlocked = false
                @unknown default:
                    break
                }
            }
            .onAppear {
            }
        }
    }

    private var title: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: model.selectedDate)) (\(model.displayedEvents.count))"
    }

    @ViewBuilder
    private func displaySelectionToggle(
        _ title: String,
        isOn: Binding<Bool>,
        isEnabled: Bool = true,
    ) -> some View {
        Toggle(title, isOn: isOn)
        .disabled(!isEnabled)
    }
}

private struct PermissionBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
    }
}

struct AboutView: View {
    @EnvironmentObject private var model: TravelsModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var statistics = AboutStatistics.empty

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 10) {
                        Image("About_Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 128, height: 128)
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                            .grayscale(1)
                            .shadow(color: .black.opacity(0.14), radius: 10, x: 0, y: 4)

                        Text("Travels")
                            .font(.custom("Noteworthy-Light", size: 36))
                            .multilineTextAlignment(.center)

                        Text(versionText)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .allowsTightening(true)
                    }
                    .frame(maxWidth: .infinity)

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            statRow("Total Locations", value: "\(statistics.totalLocations)")
                            statRow("Unique Locations", value: "\(statistics.uniqueLocations)")
                            statRow("Unaddressed Locations", value: "\(statistics.unaddressedLocations)")
                        }
                        .font(.footnote)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            contactRow(label: "Support:", title: "adigitalanalog@proton.me", url: URL(string: "mailto:adigitalanalog@proton.me"))
                            contactRow(label: "Help:", title: "adigitalanalog.com/help", url: URL(string: "https://www.adigitalanalog.com/help"))
                        }
                        .font(.caption)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Travels is licensed under the Mozilla Public License 2.0.")
                            Link("Mozilla Public License 2.0", destination: URL(string: "https://www.mozilla.org/MPL/2.0/")!)
                        }
                        .font(.footnote)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Thanks to my wife, Pam, for tolerating the ridiculous amount of time I put into this project, as well as feigning interest every time I’ve talked in detail about time zones and auto-layout.")
                        Text("© 2026 David Redmond All Rights Reserved")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
                }
                .padding()
            }
            .navigationTitle("About")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task(id: model.settings.includeDemoData) {
                statistics = model.aboutStatistics()
            }
        }
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(build)"
    }

    private func statRow(_ title: String, value: String) -> some View {
        LabeledContent(title, value: value)
    }

    private func contactRow(label: String, title: String, url: URL?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
            Button(title) {
                guard let url else { return }
                openURL(url)
            }
            .font(.caption)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .allowsTightening(true)
            .buttonStyle(.plain)
        }
    }
}

private struct DatePickerSheet: View {
    @Binding var selection: Date
    let range: ClosedRange<Date>
    let onCancel: () -> Void
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Choose a day",
                        selection: $selection,
                        in: range,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                }
            }
            .navigationTitle("Choose Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }
}

private struct LockedView: View {
    @EnvironmentObject private var model: TravelsModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill")
                .font(.system(size: 52))
            Text("Travels Locked")
                .font(.title2.bold())
            Button("Unlock") {
                model.authenticate()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
