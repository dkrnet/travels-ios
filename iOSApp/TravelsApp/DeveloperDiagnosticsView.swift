#if DEBUG
import SwiftUI

#if canImport(TravelsCore)
import TravelsCore
#endif

struct DeveloperDiagnosticsView: View {
    @EnvironmentObject private var model: TravelsModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Current Day") {
                    LabeledContent("Selected Date", value: formatted(model.selectedDate))
                    LabeledContent("Visible Events", value: "\(model.events.count)")
                    LabeledContent("Resolved Places", value: "\(resolvedVisibleEvents)")
                    LabeledContent("Unresolved Places", value: "\(model.events.count - resolvedVisibleEvents)")
                }

                Section("Resolution Queue") {
                    LabeledContent("All Events", value: "\(allEvents.count)")
                    LabeledContent("All Resolved", value: "\(allResolvedEvents)")
                    LabeledContent("All Unresolved", value: "\(allUnresolvedEvents)")
                    LabeledContent("Status", value: model.addressResolutionStatus)
                    LabeledContent("Pending", value: "\(model.addressResolutionPendingCount)")
                    LabeledContent("Current", value: model.addressResolutionCurrentTarget ?? "None")
                    LabeledContent("Last Run", value: formatted(model.addressResolutionLastRunAt))
                    LabeledContent("Last Success", value: formatted(model.addressResolutionLastSuccessAt))
                    LabeledContent("Last Error", value: model.addressResolutionLastError ?? "None")
                }

                Section("Live Settings") {
                    LabeledContent("Resolve Addresses", value: model.settings.resolveAddresses ? "On" : "Off")
                    LabeledContent("Resolve Missing", value: model.settings.resolveMissingAddresses ? "On" : "Off")
                    LabeledContent("Demo Data", value: model.settings.includeDemoData ? "On" : "Off")
                    LabeledContent("Background", value: model.settings.backgroundLocationEnabled ? "On" : "Off")
                }

                Section("Actions") {
                    Button("Run Resolution Queue Now") {
                        model.rerunAddressResolutionQueue()
                    }
                    Button("Clear Log", role: .destructive) {
                        model.clearAddressResolutionLog()
                    }
                }

                Section("Recent Log") {
                    if model.addressResolutionLog.isEmpty {
                        Text("No diagnostics yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(model.addressResolutionLog.reversed().enumerated()), id: \.offset) { _, entry in
                            Text(entry)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("Developer Diagnostics")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var resolvedVisibleEvents: Int {
        model.events.filter { event in
            guard let geolocation = event.geolocation else { return false }
            return !geolocation.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }

    private var allEvents: [EventDetail] {
        model.allEventDetails()
    }

    private var allResolvedEvents: Int {
        allEvents.filter { event in
            guard let geolocation = event.geolocation else { return false }
            return !geolocation.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }

    private var allUnresolvedEvents: Int {
        allEvents.count - allResolvedEvents
    }

    private func formatted(_ date: Date?) -> String {
        guard let date else { return "Never" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
#endif
