// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.
import SwiftUI

#if canImport(TravelsCore)
import TravelsCore
#endif

@main
struct TravelsApp: App {
    @StateObject private var model = TravelsModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .task(priority: .userInitiated) {
                    await model.bootstrap()
                }
        }
    }
}
