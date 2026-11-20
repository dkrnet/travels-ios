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
    @State private var showingMapDisabledAlert = false
    @State private var settingsScrollTarget: SettingsScrollTarget?
    @State private var openSettingsAfterWelcome = false
    @State private var shareItem: ShareItem?
    @State private var datePickerSelection = Date()
    @State private var listQuickActionShowsTop = false
    @State private var topOverlayHeight: CGFloat = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Group {
                    // REGRESSION GUARD: never construct EventMapView while the privacy setting is off; hiding an initialized map could still request Apple map tiles.
                    if model.isListView || !model.settings.mapViewEnabled {
                        EventListView(events: model.displayedEvents, topContentInset: listTopContentInset)
                            .id(model.selectedDate)
                    } else {
                        EventMapView(
                            day: model.selectedDate,
                            events: model.displayedEvents
                        )
                            .id(model.selectedDate)
                    }
                }
                .blur(radius: model.isUnlocked ? 0 : 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

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

                GeometryReader { geometry in
                    VStack {
                        DayStatusBanner(
                            title: title,
                            isHighPrecisionLocationActive: model.isHighPrecisionLocationActive,
                            availableWidth: geometry.size.width
                        )
                        .padding(.top, titleTopPadding)
                        .background(
                            GeometryReader { overlayGeometry in
                                Color.clear.preference(
                                    key: TopOverlayHeightKey.self,
                                    value: overlayGeometry.size.height
                                )
                            }
                        )
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .allowsHitTesting(false)
                .zIndex(2)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        model.selectDate(Calendar.current.date(byAdding: .day, value: -1, to: model.selectedDate) ?? model.selectedDate)
                    } label: {
                        Label("Previous Day", systemImage: "chevron.left")
                    }
                    .disabled(Calendar.current.startOfDay(for: model.selectedDate) <= model.dateSelectionRange().lowerBound)
                    Button {
                        datePickerSelection = model.clampedDateSelection(model.selectedDate)
                        showingDatePicker = true
                    } label: {
                        Label("Choose Date", systemImage: "calendar")
                    }
                    Button {
                        model.selectDate(Calendar.current.date(byAdding: .day, value: 1, to: model.selectedDate) ?? model.selectedDate)
                    } label: {
                        Label("Next Day", systemImage: "chevron.right")
                    }
                    .disabled(Calendar.current.startOfDay(for: model.selectedDate) >= model.dateSelectionRange().upperBound)
                }

                // REGRESSION GUARD: keep frequent actions separate from semantic secondary actions so Display Zoom can overflow the latter without dropping zoom/scroll access or nesting the More menu.
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        if model.isListView {
                            guard model.settings.mapViewEnabled else {
                                showingMapDisabledAlert = true
                                return
                            }
                            model.prepareMapFocusFromList()
                        } else {
                            model.prepareListScrollTargetFromMap()
                        }
                        model.isListView.toggle()
                        model.saveSettings()
                    } label: {
                        Label(
                            model.isListView ? "Show Map" : "Show List",
                            systemImage: model.isListView ? "map" : "list.bullet"
                        )
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
                            if model.mapCameraFollowMode == .showAll {
                                model.panMapToMostRecentEvent()
                            } else {
                                model.resetMapZoomToFullDay()
                            }
                        }
                    } label: {
                        Label(
                            toolbarNavigationActionTitle,
                            systemImage: model.isListView
                                ? (listQuickActionShowsTop ? "arrow.up.to.line.compact" : "arrow.down.to.line.compact")
                                : (model.mapCameraFollowMode == .showAll ? "location.fill" : "arrow.up.left.and.arrow.down.right")
                        )
                    }
                    .disabled(model.events.isEmpty)
                }

                ToolbarItemGroup(placement: .secondaryAction) {
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
                    Button("Settings") {
                        settingsScrollTarget = nil
                        showingSettings = true
                    }
                }

                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        showingSearch = true
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
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
                        Label("Select Trips", systemImage: "arrow.triangle.branch")
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
                        Label("Add Location", systemImage: "plus")
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
            .sheet(isPresented: $showingSettings, onDismiss: {
                settingsScrollTarget = nil
            }) {
                SettingsView(initialScrollTarget: settingsScrollTarget)
            }
            .sheet(
                isPresented: Binding(
                    get: { model.shouldShowFirstLaunchWelcome },
                    set: { isPresented in
                        if !isPresented {
                            model.dismissFirstLaunchWelcome()
                        }
                    }
                ),
                onDismiss: {
                    if openSettingsAfterWelcome {
                        openSettingsAfterWelcome = false
                        settingsScrollTarget = nil
                        showingSettings = true
                    }
                }
            ) {
                FirstLaunchWelcomeView(
                    demoDates: model.firstLaunchDemoDates,
                    onNotNow: {
                        model.dismissFirstLaunchWelcome()
                    },
                    onOpenSettings: {
                        openSettingsAfterWelcome = true
                        model.dismissFirstLaunchWelcome()
                    }
                )
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
            .alert("Map View Disabled", isPresented: $showingMapDisabledAlert) {
                Button("Open Settings") {
                    settingsScrollTarget = .mapView
                    showingSettings = true
                }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text("Map View is off to avoid downloading map tiles from Apple. You can enable it in Settings under Display.")
            }
            .onChange(of: model.selectedDate) { _, _ in
                listQuickActionShowsTop = false
            }
            .onChange(of: model.isListView) { _, _ in
                if model.isListView {
                    listQuickActionShowsTop = false
                }
            }
            .onChange(of: model.settings.mapViewEnabled) { _, isEnabled in
                if !isEnabled {
                    model.disableMapViewForPrivacy()
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
            .onPreferenceChange(TopOverlayHeightKey.self) { height in
                topOverlayHeight = height
            }
        }
    }

    private var title: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: model.selectedDate)) (\(model.displayedEvents.count))"
    }

    private var titleTopPadding: CGFloat {
        8
    }

    private var listTopContentInset: CGFloat {
        max(24, topOverlayHeight)
    }

    private var toolbarNavigationActionTitle: String {
        if model.isListView {
            return listQuickActionShowsTop ? "Scroll to Top" : "Scroll to Bottom"
        }
        return model.mapCameraFollowMode == .showAll ? "Show Latest" : "Show All"
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

private struct TopOverlayHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct DayStatusBanner: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let title: String
    let isHighPrecisionLocationActive: Bool
    let availableWidth: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: titleFontSize, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .layoutPriority(2)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            if isHighPrecisionLocationActive {
                HStack(spacing: 5) {
                    Image(systemName: "location.fill")
                        .font(.system(size: preciseFontSize, weight: .semibold))
                    Text("Precise Location")
                        .font(.system(size: preciseFontSize, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .foregroundStyle(.primary)
                .layoutPriority(1)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Precise Location")
                .accessibilityHint("Travels is currently using high-accuracy location tracking.")
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 14)
        .frame(width: max(availableWidth, 0), alignment: .leading)
        .background {
            if reduceTransparency {
                Rectangle()
                    .fill(.background)
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 0.5)
        }
        .shadow(color: .black.opacity(0.035), radius: 5, x: 0, y: 2)
    }

    private var preciseFontSize: CGFloat {
        titleFontSize * 0.67
    }

    private var titleFontSize: CGFloat {
        min(max(availableWidth * 0.05, 18), 24)
    }
}

private struct DayTitleOverlay: View {
    let title: String
    let availableWidth: CGFloat

    var body: some View {
        Text(title)
            .font(.system(size: titleFontSize, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.vertical, 5)
            .padding(.horizontal, 12)
            .background(.thinMaterial, in: Capsule())
            .frame(maxWidth: max(availableWidth - 32, 0))
            .accessibilityAddTraits(.isHeader)
    }

    private var titleFontSize: CGFloat {
        min(max(availableWidth * 0.055, 20), 26)
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
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Your location history. On your device.")
                                .font(.headline)
                            Text("Travels is a privacy-first location history app. It records and organizes your location history locally on your device, without accounts, subscriptions, advertising, analytics, or cloud tracking.")
                            privacyDisclosureRow("Your location history is stored locally.", systemImage: "iphone")
                            privacyDisclosureRow("Map View is off by default. When enabled, Apple receives the requests needed to download map tiles for the areas you view.", systemImage: "map")
                            privacyDisclosureRow("Address lookup is optional and sends coordinates to Apple only when enabled.", systemImage: "mappin.and.ellipse")
                            privacyDisclosureRow("Data leaves Travels only when you export or share it, or when an enabled feature uses an Apple platform service.", systemImage: "square.and.arrow.up")
                        }
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("I created Travels because I wanted a privacy-first way to keep my own location history. It’s free because this is a niche app, and charging for it would add more complexity than value.")
                            Text("You are not the product. Travels has no business model based on selling your location data.")
                                .fontWeight(.semibold)
                        }
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Text("Why Travels Is Free")
                            .font(.headline)
                    }

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
                            contactRow(label: "Support:", title: "travels-ios@proton.me", url: URL(string: "mailto:travels-ios@proton.me"))
                            contactRow(label: "Help:", title: "github.com/dkrnet/travels-ios", url: URL(string: "https://github.com/dkrnet/travels-ios"))
                        }
                        .font(.caption)
                    }

                    GroupBox {
                        Text("Travels is licensed under the [Mozilla Public License 2.0](https://www.mozilla.org/MPL/2.0/).")
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
        let displayVersion = info?["TravelsDisplayVersion"] as? String
        let fallbackVersion = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(displayVersion ?? fallbackVersion)"
    }

    private func statRow(_ title: String, value: String) -> some View {
        LabeledContent(title, value: value)
    }

    private func privacyDisclosureRow(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .frame(width: 20)
        }
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
