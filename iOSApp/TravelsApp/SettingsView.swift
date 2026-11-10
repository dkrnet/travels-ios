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
                        Text("Lets Travels ask for Always Location access so it can keep recording when you leave the app.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("Location Detail", selection: $model.settings.locationDetailMode) {
                            ForEach(LocationDetailMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text("Controls how many automatic location points are saved. High Detail saves more points. Road Trip saves fewer points at sustained highway speed while still capturing exits, towns, and stops.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("Precise Location Mode", selection: $model.settings.preciseLocationMode) {
                            ForEach(PreciseLocationMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text("Automatic uses precise location only while movement is being tracked. Always On keeps precise tracking active while automatic tracking is enabled. Always Off uses lower-power monitoring plus manual location capture.")
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
                        Text("Travels provides silent actions to capture filtered, non-duplicate, stopped, and forced locations, plus actions to turn Automatic Location Tracking on or off. Non-Duplicate actions save only when the new location is more than 20 meters from the previous event. Stopped actions set the movement override without changing measured speed.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("In Shortcuts, create a personal automation for Wi-Fi, Bluetooth, or Charger, choose Run Immediately, then add the preferred Travels location action. Enable or disable each trigger from the Automation tab in Shortcuts.")
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
