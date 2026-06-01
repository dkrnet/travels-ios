// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import TravelsCore

struct SearchView: View {
    @EnvironmentObject private var model: TravelsModel
    @Environment(\.dismiss) private var dismiss
    @State private var term = ""
    @State private var hasNote = false
    @State private var source: EventSource?

    var body: some View {
        NavigationStack {
            List {
                Section("Filters") {
                    TextField("Search", text: $term)
                    Toggle("Has Note", isOn: $hasNote)
                    Picker("Source", selection: $source) {
                        Text("Any").tag(EventSource?.none)
                        ForEach(EventSource.allCases.filter { $0 != .invalid }, id: \.self) { source in
                            Text(source.displayName).tag(EventSource?.some(source))
                        }
                    }
                }

                Section("Results") {
                    ForEach(model.searchResults) { detail in
                        EventRow(detail: detail)
                            .onTapGesture {
                                model.selectedDate = detail.event.timestamp
                                model.selectedEvent = detail
                                dismiss()
                            }
                    }
                }
            }
            .navigationTitle("Search")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Search") {
                        model.search(SearchCriteria(term: term, hasNote: hasNote, source: source))
                    }
                }
            }
        }
    }
}
