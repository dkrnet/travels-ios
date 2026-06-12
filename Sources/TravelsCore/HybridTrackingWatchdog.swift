// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.

import Foundation

public enum HybridTrackingWatchdogState: Equatable, Sendable {
    case idle
    case scheduled(nextRecheckAt: Date)
}

public struct HybridTrackingWatchdog: Equatable, Sendable {
    public var policy: LocationTrackingPolicy
    public var interval: TimeInterval
    public private(set) var state: HybridTrackingWatchdogState

    public init(
        policy: LocationTrackingPolicy = .hybridAutomatic,
        interval: TimeInterval = 90
    ) {
        self.policy = policy
        self.interval = interval
        self.state = .idle
    }

    public var isRunning: Bool {
        if case .scheduled = state {
            return true
        }
        return false
    }

    public mutating func update(policy newPolicy: LocationTrackingPolicy) {
        policy = newPolicy
        if newPolicy == .alwaysOnHighPrecision {
            cancel()
        }
    }

    public mutating func start(now: Date) {
        guard policy == .hybridAutomatic else {
            cancel()
            return
        }
        state = .scheduled(nextRecheckAt: now.addingTimeInterval(interval))
    }

    public mutating func cancel() {
        state = .idle
    }

    public mutating func shouldRequestRecheck(now: Date) -> Bool {
        guard policy == .hybridAutomatic else {
            cancel()
            return false
        }
        guard case .scheduled(let nextRecheckAt) = state, now >= nextRecheckAt else {
            return false
        }
        state = .scheduled(nextRecheckAt: now.addingTimeInterval(interval))
        return true
    }
}
