// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.
import SwiftUI

#if canImport(TravelsCore)
import TravelsCore
#endif

struct SearchView: View {
    @EnvironmentObject private var model: TravelsModel
    @Environment(\.dismiss) private var dismiss
    @State private var term = ""
    @State private var hasNote = false
    @State private var source: EventSource?
    @State private var useStartDate = false
    @State private var startDate = Calendar.current.startOfDay(for: Date())
    @State private var useEndDate = false
    @State private var endDate = Calendar.current.startOfDay(for: Date())
    @State private var placeOptions = SearchPlaceOptions.empty
    @State private var country: String?
    @State private var administrativeArea: String?
    @State private var subAdministrativeArea: String?
    @State private var locality: String?
    @State private var bodyOfWater: String?
    @State private var searchResultsScrollCommandID = UUID()

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section("Filters") {
                        TextField("Search text", text: $term)
                        Toggle("Has Note", isOn: $hasNote)
                        Picker("Source", selection: $source) {
                            Text("Any").tag(EventSource?.none)
                            ForEach(EventSource.allCases.filter { $0 != .invalid }, id: \.self) { source in
                                Text(source.displayName).tag(EventSource?.some(source))
                            }
                        }
                    }

                    Section("Date Range") {
                        Toggle("From Date", isOn: $useStartDate)
                        if useStartDate {
                            DatePicker("After", selection: $startDate, displayedComponents: .date)
                        }
                        Toggle("Before Date", isOn: $useEndDate)
                        if useEndDate {
                            DatePicker("Before", selection: $endDate, displayedComponents: .date)
                        }
                    }

                    Section("Place Filters") {
                        Picker("Country", selection: $country) {
                            Text("Any").tag(String?.none)
                            ForEach(placeOptions.countries, id: \.self) { value in
                                Text(value).tag(String?.some(value))
                            }
                        }
                        Picker("Administrative Area", selection: $administrativeArea) {
                            Text("Any").tag(String?.none)
                            ForEach(placeOptions.administrativeAreas, id: \.self) { value in
                                Text(value).tag(String?.some(value))
                            }
                        }
                        Picker("Sub-Administrative Area", selection: $subAdministrativeArea) {
                            Text("Any").tag(String?.none)
                            ForEach(placeOptions.subAdministrativeAreas, id: \.self) { value in
                                Text(value).tag(String?.some(value))
                            }
                        }
                        Picker("Locality", selection: $locality) {
                            Text("Any").tag(String?.none)
                            ForEach(placeOptions.localities, id: \.self) { value in
                                Text(value).tag(String?.some(value))
                            }
                        }
                        Picker("Body of Water", selection: $bodyOfWater) {
                            Text("Any").tag(String?.none)
                            ForEach(placeOptions.bodyOfWaters, id: \.self) { value in
                                Text(value).tag(String?.some(value))
                            }
                        }
                        Text("Place filters use exact matches from saved locations.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("Results") {
                        Color.clear
                            .frame(height: 1)
                            .id(resultsAnchorID)
                        if model.searchResults.isEmpty {
                            Text("Run a search to see matching events.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(model.searchResults) { detail in
                                EventRow(detail: detail)
                                    .onTapGesture {
                                        if let id = detail.id {
                                            model.focusAfterCapture(eventID: id, timestamp: detail.event.timestamp)
                                        }
                                        dismiss()
                                    }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .navigationTitle("Search")
                .task(id: filterSignature) {
                    refreshPlaceOptions()
                }
                .task(id: searchResultsScrollCommandID) {
                    guard !model.searchResults.isEmpty else { return }
                    await Task.yield()
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(resultsAnchorID, anchor: .top)
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Search") {
                            model.search(searchCriteria)
                            searchResultsScrollCommandID = UUID()
                        }
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Reset") {
                            clearFilters()
                        }
                    }
                }
                .onAppear {
                    refreshPlaceOptions()
                }
            }
        }
    }

    private let resultsAnchorID = "search-results-anchor"

    private var searchCriteria: SearchCriteria {
        SearchCriteria(
            term: term,
            startDate: useStartDate ? Calendar.current.startOfDay(for: startDate) : nil,
            endDate: useEndDate ? Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endDate)) : nil,
            hasNote: hasNote,
            country: country,
            administrativeArea: administrativeArea,
            subAdministrativeArea: subAdministrativeArea,
            locality: locality,
            bodyOfWater: bodyOfWater,
            source: source
        )
    }

    private var filterSignature: String {
        [
            term,
            hasNote ? "1" : "0",
            source.map { String($0.rawValue) } ?? "",
            useStartDate ? "1" : "0",
            startDate.formatted(.dateTime.year().month().day()),
            useEndDate ? "1" : "0",
            endDate.formatted(.dateTime.year().month().day()),
            country ?? "",
            administrativeArea ?? "",
            subAdministrativeArea ?? "",
            locality ?? "",
            bodyOfWater ?? ""
        ].joined(separator: "|")
    }

    private func refreshPlaceOptions() {
        let options = model.searchPlaceOptions(matching: searchCriteria)
        placeOptions = options

        var needsRefresh = false

        if let selected = country, !options.countries.contains(selected) {
            country = nil
            administrativeArea = nil
            subAdministrativeArea = nil
            locality = nil
            bodyOfWater = nil
            needsRefresh = true
        } else if let selected = administrativeArea, !options.administrativeAreas.contains(selected) {
            administrativeArea = nil
            subAdministrativeArea = nil
            locality = nil
            bodyOfWater = nil
            needsRefresh = true
        } else if let selected = subAdministrativeArea, !options.subAdministrativeAreas.contains(selected) {
            subAdministrativeArea = nil
            locality = nil
            bodyOfWater = nil
            needsRefresh = true
        } else if let selected = locality, !options.localities.contains(selected) {
            locality = nil
            bodyOfWater = nil
            needsRefresh = true
        } else if let selected = bodyOfWater, !options.bodyOfWaters.contains(selected) {
            bodyOfWater = nil
            needsRefresh = true
        }

        if needsRefresh {
            refreshPlaceOptions()
        }
    }

    private func clearFilters() {
        term = ""
        hasNote = false
        source = nil
        useStartDate = false
        useEndDate = false
        country = nil
        administrativeArea = nil
        subAdministrativeArea = nil
        locality = nil
        bodyOfWater = nil
        model.searchResults = []
    }
}
