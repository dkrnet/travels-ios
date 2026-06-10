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
                        Toggle("Resolve Addresses", isOn: $model.settings.resolveAddresses)
                        Text("Anonymously sends location data to Apple so Travels can look up place names.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Resolve Missing Addresses", isOn: $model.settings.resolveMissingAddresses)
                        Text("Look up addresses for location history that still needs it.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Stepper("Powered Distance: \(formatted(model.settings.poweredUpdateDistanceMeters))", value: $model.settings.poweredUpdateDistanceMeters, in: 100...10_000, step: 100)
                        Text("Minimum distance before saving a new point while charging or on power.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Stepper("Battery Distance: \(formatted(model.settings.batteryUpdateDistanceMeters))", value: $model.settings.batteryUpdateDistanceMeters, in: 100...10_000, step: 100)
                        Text("Minimum distance before saving a new point while on battery.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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

    private func formatted(_ meters: Int) -> String {
        formattedLengthText(Double(meters), measurementSystem: model.settings.preferredMeasurementSystem)
    }
}
