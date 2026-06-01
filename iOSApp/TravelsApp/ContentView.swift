// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import MapKit
import SwiftUI
import TravelsCore
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: TravelsModel
    @State private var showingSettings = false
    @State private var showingSearch = false
    @State private var showingImporter = false

    var body: some View {
        NavigationStack {
            ZStack {
                Group {
                    if model.isListView {
                        EventListView(events: model.events)
                    } else {
                        EventMapView(events: model.events)
                    }
                }
                .blur(radius: model.isUnlocked ? 0 : 18)

                if !model.isUnlocked {
                    LockedView()
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        model.selectDate(Calendar.current.date(byAdding: .day, value: -1, to: model.selectedDate) ?? model.selectedDate)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    Button {
                        model.selectDate(Date())
                    } label: {
                        Image(systemName: "calendar")
                    }
                    Button {
                        model.selectDate(Calendar.current.date(byAdding: .day, value: 1, to: model.selectedDate) ?? model.selectedDate)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        model.isListView.toggle()
                        model.saveSettings()
                    } label: {
                        Image(systemName: model.isListView ? "map" : "list.bullet")
                    }
                    Button {
                        showingSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    Menu {
                        Button("Import GPX") { showingImporter = true }
                        Button("Settings") { showingSettings = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(item: $model.selectedEvent) { detail in
                EventDetailView(detail: detail)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingSearch) {
                SearchView()
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    model.importGPX(url: url)
                }
            }
            .alert("Travels", isPresented: Binding(get: { model.statusMessage != nil }, set: { if !$0 { model.statusMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.statusMessage ?? "")
            }
        }
    }

    private var title: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: model.selectedDate)) (\(model.events.count))"
    }
}

private struct LockedView: View {
    @EnvironmentObject private var model: TravelsModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill")
                .font(.system(size: 52))
            Text("Travels Locked")
                .font(.title2.bold())
            Button("Unlock") {
                model.authenticate()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
