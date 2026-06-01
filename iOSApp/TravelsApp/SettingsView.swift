// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import TravelsCore

struct SettingsView: View {
    @EnvironmentObject private var model: TravelsModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Tracking") {
                    Toggle("Automatic Location Tracking", isOn: $model.settings.autoAddLocations)
                    Toggle("Resolve Addresses", isOn: $model.settings.resolveAddresses)
                    Toggle("Resolve Missing Addresses", isOn: $model.settings.resolveMissingAddresses)
                    Stepper("Powered Distance: \(formatted(model.settings.poweredUpdateDistanceMeters))", value: $model.settings.poweredUpdateDistanceMeters, in: 100...10_000, step: 100)
                    Stepper("Battery Distance: \(formatted(model.settings.batteryUpdateDistanceMeters))", value: $model.settings.batteryUpdateDistanceMeters, in: 100...10_000, step: 100)
                }

                Section("Display") {
                    Toggle("Include Previous Day Context", isOn: $model.settings.includePreviousDayContext)
                    Toggle("Include Demo Data", isOn: $model.settings.includeDemoData)
                    Toggle("Prefer List View", isOn: $model.isListView)
                }

                Section("Privacy") {
                    Toggle("Require Authentication", isOn: $model.settings.requireAuthentication)
                }

                Section {
                    Text("Address resolution may send coordinates anonymously to Apple. Location updates are best effort and can vary with battery, signal, and iOS power management.")
                        .font(.footnote)
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
        }
    }

    private func formatted(_ meters: Int) -> String {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.numberStyle = .decimal
        return formatter.string(from: Measurement(value: Double(meters), unit: UnitLength.meters))
    }
}
