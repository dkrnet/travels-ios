// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.

// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.
import AppIntents

#if DEBUG
enum CarPlayDiagnosticEventType: String, AppEnum {
    case connected
    case disconnected

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "CarPlay Event")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .connected: "Connected",
        .disconnected: "Disconnected"
    ]
}

struct LogCarPlayEventIntent: AppIntent {
    static let title: LocalizedStringResource = "Log CarPlay Event"
    static let description = IntentDescription(
        "Records a CarPlay connect or disconnect event with Travels' current tracking state for diagnostics."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Event Type")
    var eventType: CarPlayDiagnosticEventType

    static var parameterSummary: some ParameterSummary {
        Summary("Log CarPlay \(\.$eventType)")
    }

    func perform() async throws -> some IntentResult {
        await TravelsModel.shared.recordCarPlayConnectionEventFromShortcut(eventType.rawValue)
        return .result()
    }
}
#endif

struct AddLocationIntent: AppIntent, LongRunningIntent {
    static let title: LocalizedStringResource = "Add"
    static let description = IntentDescription(
        "Requests one location with optional forced, stopped, and non-duplicate behavior."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Forced", default: false)
    var forced: Bool

    @Parameter(title: "Stopped", default: false)
    var stopped: Bool

    @Parameter(title: "Non-Duplicate", default: false)
    var nonDuplicate: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Add location (Forced: \(\.$forced), Stopped: \(\.$stopped), Non-Duplicate: \(\.$nonDuplicate))")
    }

    func perform() async throws -> some IntentResult {
        // REGRESSION GUARD: Automation-triggered captures must remain silent. Non-Duplicate
        // deliberately takes precedence over Forced so nearby locations are never inserted.
        _ = await TravelsModel.shared.captureLocationFromShortcut(
            forced: forced,
            stopped: stopped,
            nonDuplicate: nonDuplicate
        )
        return .result()
    }
}

struct DisableAutomaticLocationTrackingIntent: AppIntent {
    static let title: LocalizedStringResource = "Tracking Off"
    static let description = IntentDescription("Turns off Travels automatic location tracking.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        await TravelsModel.shared.setAutomaticLocationTrackingFromShortcut(false)
        return .result()
    }
}

struct EnableAutomaticLocationTrackingIntent: AppIntent {
    static let title: LocalizedStringResource = "Tracking On"
    static let description = IntentDescription("Turns on Travels automatic location tracking.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        await TravelsModel.shared.setAutomaticLocationTrackingFromShortcut(true)
        return .result()
    }
}

struct TravelsAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
#if DEBUG
        AppShortcut(
            intent: LogCarPlayEventIntent(),
            phrases: [
                "Log a CarPlay event in \(.applicationName)"
            ],
            shortTitle: "Log CarPlay Event",
            systemImageName: "car.side"
        )
#endif
        AppShortcut(
            intent: AddLocationIntent(),
            phrases: [
                "Add my current location in \(.applicationName)",
                "Save my current location in \(.applicationName)"
            ],
            shortTitle: "Add",
            systemImageName: "location.fill"
        )
        AppShortcut(
            intent: DisableAutomaticLocationTrackingIntent(),
            phrases: [
                "Turn off automatic location tracking in \(.applicationName)",
                "Stop automatic location tracking in \(.applicationName)"
            ],
            shortTitle: "Tracking Off",
            systemImageName: "location.slash"
        )
        AppShortcut(
            intent: EnableAutomaticLocationTrackingIntent(),
            phrases: [
                "Turn on automatic location tracking in \(.applicationName)",
                "Start automatic location tracking in \(.applicationName)"
            ],
            shortTitle: "Tracking On",
            systemImageName: "location.fill"
        )
    }
}
