// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public final class SettingsStore: @unchecked Sendable {
    private let store: TravelsStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let key = "modern.appSettings"

    public init(store: TravelsStore) {
        self.store = store
    }

    public func load() throws -> AppSettings {
        guard let raw = try store.setting(key), let data = raw.data(using: .utf8) else {
            return AppSettings()
        }
        return try decoder.decode(AppSettings.self, from: data)
    }

    public func save(_ settings: AppSettings) throws {
        let data = try encoder.encode(settings)
        guard let raw = String(data: data, encoding: .utf8) else {
            return
        }
        try store.setSetting(key, value: raw)
    }
}
