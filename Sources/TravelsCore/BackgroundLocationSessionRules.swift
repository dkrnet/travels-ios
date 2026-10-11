// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.

import Foundation

public enum BackgroundLocationSessionRules {
    public static func shouldRetainSession(
        automaticTrackingEnabled: Bool,
        backgroundLocationEnabled: Bool,
        hasLocationAuthorization: Bool,
        preciseBackgroundTrackingAllowed: Bool
    ) -> Bool {
        automaticTrackingEnabled
            && backgroundLocationEnabled
            && hasLocationAuthorization
            && preciseBackgroundTrackingAllowed
    }

    public static func shouldReplaceSessionAfterForegrounding(
        hasSession: Bool,
        sessionWasCreatedInForeground: Bool
    ) -> Bool {
        hasSession && !sessionWasCreatedInForeground
    }
}
