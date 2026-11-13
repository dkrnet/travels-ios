// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.

// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.
import AppIntents

extension LocationCaptureMode: AppEnum {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Mode")
    public static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .normal: "Normal",
        .force: "Force",
        .ifNew: "If New"
    ]
}

extension LocationCaptureMovement: AppEnum {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Movement")
    public static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .automatic: "Automatic",
        .stopped: "Stopped",
        .moving: "Moving"
    ]
}

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
        "Requests one location using the selected recording mode and movement classification."
    )
    static let openAppWhenRun = false

    @Parameter(
        title: "Mode",
        description: "Choose normal filtering, force recording, or record only when the location is new.",
        default: .normal
    )
    var mode: LocationCaptureMode

    @Parameter(
        title: "Movement",
        description: "Choose automatic detection or explicitly classify the location as stopped or moving.",
        default: .automatic
    )
    var movement: LocationCaptureMovement

    static var parameterSummary: some ParameterSummary {
        When(\.$mode, .equalTo, .normal) {
            When(\.$movement, .equalTo, .automatic) {
                Summary("Add location")
            } otherwise: {
                When(\.$movement, .equalTo, .stopped) {
                    Summary("Add stopped location")
                } otherwise: {
                    Summary("Add moving location")
                }
            }
        } otherwise: {
            When(\.$mode, .equalTo, .force) {
                When(\.$movement, .equalTo, .automatic) {
                    Summary("Force add location")
                } otherwise: {
                    When(\.$movement, .equalTo, .stopped) {
                        Summary("Force add stopped location")
                    } otherwise: {
                        Summary("Force add moving location")
                    }
                }
            } otherwise: {
                When(\.$movement, .equalTo, .automatic) {
                    Summary("Add location if new")
                } otherwise: {
                    When(\.$movement, .equalTo, .stopped) {
                        Summary("Add stopped location if new")
                    } otherwise: {
                        Summary("Add moving location if new")
                    }
                }
            }
        }
    }

    func perform() async throws -> some IntentResult {
        // REGRESSION GUARD: Automation-triggered captures must remain silent. Keep the
        // existing intent type stable so saved Shortcuts retain their action identity.
        _ = await TravelsModel.shared.captureLocationFromShortcut(
            mode: mode,
            movement: movement
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
