// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.
import SwiftUI

#if canImport(TravelsCore)
import TravelsCore
#endif

struct SettingsView: View {
    @EnvironmentObject private var model: TravelsModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Tracking") {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Automatic Location Tracking", isOn: $model.settings.autoAddLocations)
                        Text("Turns automatic location tracking on and off.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Background Location", isOn: $model.settings.backgroundLocationEnabled)
                        Text("Lets Travels ask for Always **Location Access** so it can keep recording when you leave the app.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("Location Density", selection: $model.settings.locationDetailMode) {
                            ForEach(LocationDetailMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text("Controls the density of automatically saved location points. **High Detail** saves more points. **Road Trip** saves fewer points at sustained highway speed.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("Location Precision", selection: $model.settings.preciseLocationMode) {
                            ForEach(PreciseLocationMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text("Controls when the app uses high-precision location tracking. **Automatic** uses high precision only while moving, **Always On** keeps it active whenever automatic tracking is enabled, and **Always Off** relies on battery-saving monitoring and manual captures.")

                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Resolve Addresses", isOn: $model.settings.resolveAddresses)
                        Text("Address lookup is optional and sends coordinates to Apple only when enabled.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Resolve Missing Addresses", isOn: $model.settings.resolveMissingAddresses)
                        Text("Look up addresses for location history that still needs it.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Shortcuts Automations") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Travels provides three background Shortcuts actions: **Tracking On**, **Tracking Off**, and **Add Location**. When adding a location, you can choose whether it saves unconditionally or only after you've moved a minimum distance, and optionally override your movement status without changing your measured speed.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("""
                        1. Open the **Shortcuts** app and go to the **Automation** tab.
                        2. Create a personal automation using a trigger like **Wi-Fi**, **Bluetooth**, or **CarPlay**.
                        3. Select **Run Immediately** and add your preferred Travels action.
                        4. Toggle triggers on or off anytime from the **Automation** tab.
                        """)
                           .font(.footnote)
                            .foregroundStyle(.secondary)
                        Link("Open Shortcuts", destination: URL(string: "shortcuts://")!)
                    }
                }

                Section("Units") {
                    Picker("Preferred Units", selection: $model.settings.preferredMeasurementSystem) {
                        ForEach(MeasurementSystemPreference.allCases, id: \.self) { system in
                            Text(system.displayName).tag(system)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Display") {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Enable Map View", isOn: $model.settings.mapViewEnabled)
                        Text("Map View downloads map tiles from Apple. When enabled, Apple receives network requests for the areas you view. Leave it off to browse your saved history as a local list without sending map requests.")

                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Include Previous Day Context", isOn: $model.settings.includePreviousDayContext)
                        Text("Shows the tail end of the prior day so trips feel continuous.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Include Demo Data", isOn: $model.settings.includeDemoData)
                        Text("Shows sample locations that ship with the app.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Privacy") {
                    Text("Travels stores your location history locally and does not use accounts, advertising, analytics, or cloud tracking.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Require Authentication", isOn: $model.settings.requireAuthentication)
                        Text("Requires Face ID or Touch ID before opening your map and list.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.saveSettings()
                        dismiss()
                    }
                }
            }
            .alert("Travels", isPresented: Binding(get: { model.statusMessage != nil }, set: { if !$0 { model.statusMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.statusMessage ?? "")
            }
        }
    }
}

struct FirstLaunchWelcomeView: View {
    let demoDates: [Date]
    let onNotNow: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        Text("Travels keeps a private history of the places you've been. Your location history is stored only on this device and is never sent to the developer.")
                    } icon: {
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(.blue)
                    }
                }

                Section("Record in the Background") {
                    Text("Automatic Location Tracking is enabled by default. Background Location remains off until you choose to enable it.")
                    VStack(alignment: .leading, spacing: 10) {
                        welcomeStep(1, "Open Travels Settings.")
                        welcomeStep(2, "Leave Automatic Location Tracking on and enable Background Location.")
                        welcomeStep(3, "Choose Always Allow when iOS asks for location access.")
                    }
                }

                Section("What to Expect") {
                    Text("With Location Precision set to Automatic, Travels normally uses lower-power monitoring and temporarily increases location accuracy when movement is detected.")
                    Text("Background tracking uses additional battery and may cause iOS to display its location indicator.")
                    Text("Address lookup is optional and sends coordinates to Apple only when enabled.")
                    Text("Map View is off by default. Enabling it downloads map tiles from Apple; you can enable it later in Settings.")
                }

                if let firstDemoDate = demoDates.first, let lastDemoDate = demoDates.last {
                    Section("Demo Data") {
                        Text("Sample trips dated \(firstDemoDate.formatted(date: .abbreviated, time: .omitted)) through \(lastDemoDate.formatted(date: .abbreviated, time: .omitted)) have been added. You can hide them by turning off Include Demo Data in Settings.")
                    }
                }

                Section {
                    Text("You can change these options at any time from the Travels menu under Settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now", action: onNotNow)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open Settings", action: onOpenSettings)
                }
            }
        }
    }

    private func welcomeStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(.blue, in: Circle())
            Text(text)
        }
    }
}
