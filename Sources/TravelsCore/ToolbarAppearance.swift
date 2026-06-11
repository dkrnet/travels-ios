// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public enum ButtonForegroundTone: Equatable, Sendable {
    case primary
    case tertiary

    public static func addButton(canAddCurrentLocation: Bool) -> ButtonForegroundTone {
        canAddCurrentLocation ? .primary : .tertiary
    }
}
