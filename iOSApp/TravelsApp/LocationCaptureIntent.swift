// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.

// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.
import AppIntents

struct CaptureCurrentLocationIntent: AppIntent, LongRunningIntent {
    static let title: LocalizedStringResource = "Add"
    static let description = IntentDescription(
        "Requests one location and processes it through Travels' normal automatic filtering and storage rules."
    )
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        // REGRESSION GUARD: Automation-triggered captures must remain silent so they never require user interaction.
        _ = await TravelsModel.shared.captureCurrentLocationFromShortcut()
        return .result()
    }
}

struct ForceAddCurrentLocationIntent: AppIntent, LongRunningIntent {
    static let title: LocalizedStringResource = "Add Forced"
    static let description = IntentDescription(
        "Requests one location and saves it through Travels' manual Add path, bypassing normal location filtering."
    )
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        // REGRESSION GUARD: Automation-triggered captures must remain silent so they never require user interaction.
        _ = await TravelsModel.shared.forceAddCurrentLocationFromShortcut()
        return .result()
    }
}

struct CaptureStoppedLocationIntent: AppIntent, LongRunningIntent {
    static let title: LocalizedStringResource = "Stopped"
    static let description = IntentDescription(
        "Requests one normally filtered location and marks it as stopped if Travels accepts it."
    )
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        // REGRESSION GUARD: This action remains silent and must not bypass normal filtering.
        _ = await TravelsModel.shared.captureStoppedLocationFromShortcut()
        return .result()
    }
}

struct CaptureNonDuplicateLocationIntent: AppIntent, LongRunningIntent {
    static let title: LocalizedStringResource = "Non-Duplicate"
    static let description = IntentDescription(
        "Force adds the current location only when it is more than 20 meters from the previous event."
    )
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        _ = await TravelsModel.shared.captureNonDuplicateLocationFromShortcut()
        return .result()
    }
}

struct CaptureStoppedNonDuplicateLocationIntent: AppIntent, LongRunningIntent {
    static let title: LocalizedStringResource = "Stopped Non-Duplicate"
    static let description = IntentDescription(
        "Force adds the current location when it is more than 20 meters from the previous event and marks an accepted event as stopped."
    )
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        _ = await TravelsModel.shared.captureNonDuplicateLocationFromShortcut(stopped: true)
        return .result()
    }
}

struct ForceAddStoppedLocationIntent: AppIntent, LongRunningIntent {
    static let title: LocalizedStringResource = "Stopped Forced"
    static let description = IntentDescription(
        "Force adds the current location and marks it as stopped without changing its measured speed."
    )
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        _ = await TravelsModel.shared.forceAddStoppedLocationFromShortcut()
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
        AppShortcut(
            intent: CaptureCurrentLocationIntent(),
            phrases: [
                "Capture my current location in \(.applicationName)",
                "Save my current location in \(.applicationName)"
            ],
            shortTitle: "Add",
            systemImageName: "location.fill"
        )
        AppShortcut(
            intent: ForceAddCurrentLocationIntent(),
            phrases: [
                "Force add my current location in \(.applicationName)",
                "Force save my current location in \(.applicationName)"
            ],
            shortTitle: "Add Forced",
            systemImageName: "location.fill.viewfinder"
        )
        AppShortcut(
            intent: CaptureStoppedLocationIntent(),
            phrases: [
                "Capture my stopped location in \(.applicationName)",
                "Save my stopped location in \(.applicationName)"
            ],
            shortTitle: "Stopped",
            systemImageName: "mappin.and.ellipse"
        )
        AppShortcut(
            intent: ForceAddStoppedLocationIntent(),
            phrases: [
                "Force add a stopped location in \(.applicationName)",
                "Force save a stopped location in \(.applicationName)"
            ],
            shortTitle: "Stopped Forced",
            systemImageName: "mappin.and.ellipse.circle.fill"
        )
        AppShortcut(
            intent: CaptureNonDuplicateLocationIntent(),
            phrases: [
                "Capture a non duplicate location in \(.applicationName)",
                "Save a non duplicate location in \(.applicationName)"
            ],
            shortTitle: "Non-Duplicate",
            systemImageName: "location.circle"
        )
        AppShortcut(
            intent: CaptureStoppedNonDuplicateLocationIntent(),
            phrases: [
                "Capture a stopped non duplicate location in \(.applicationName)",
                "Save a stopped non duplicate location in \(.applicationName)"
            ],
            shortTitle: "Stopped Non-Duplicate",
            systemImageName: "mappin.circle"
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
