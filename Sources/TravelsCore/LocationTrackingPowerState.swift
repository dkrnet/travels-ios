// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.

import Foundation

public enum DeviceBatteryState: String, Codable, CaseIterable, Sendable {
    case charging
    case full
    case unplugged
    case unknown
}

public struct LocationTrackingPowerState: Equatable, Sendable {
    public var batteryState: DeviceBatteryState
    public var lowPowerModeEnabled: Bool

    public init(
        batteryState: DeviceBatteryState = .unknown,
        lowPowerModeEnabled: Bool = false
    ) {
        self.batteryState = batteryState
        self.lowPowerModeEnabled = lowPowerModeEnabled
    }

    public var shouldPauseAutomatically: Bool {
        batteryState != .charging && batteryState != .full
    }

    public var usesPoweredDistanceThreshold: Bool {
        batteryState == .charging || batteryState == .full
    }

    public func requiresConfigurationRefresh(comparedTo other: LocationTrackingPowerState) -> Bool {
        self != other
    }
}
