// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.

import Foundation

public enum CurrentLocationCaptureAvailability {
    public static func canAddCurrentLocation(
        selectedDate: Date,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        locationServicesEnabled: Bool,
        hasLocationPermission: Bool,
        isUnlocked: Bool
    ) -> Bool {
        // Regression guard: this availability check intentionally centralizes every reason the
        // Add action must be hidden or disabled so the UI stays truthful on all devices.
        guard isUnlocked else { return false }
        guard locationServicesEnabled else { return false }
        guard hasLocationPermission else { return false }
        return calendar.isDate(selectedDate, inSameDayAs: now)
    }
}
