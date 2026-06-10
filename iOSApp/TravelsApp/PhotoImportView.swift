// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.

// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.
import PhotosUI
import SwiftUI
import UIKit

#if canImport(TravelsCore)
import TravelsCore
#endif

struct PhotoImportView: View {
    @EnvironmentObject private var model: TravelsModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var drafts: [PhotoImportDraft] = []
    @State private var isLoadingPreviews = false
    @State private var isImporting = false
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Photo") {
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: nil,
                        selectionBehavior: .ordered,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("Choose Photos", systemImage: "photo.on.rectangle.angled")
                    }
                    if !drafts.isEmpty {
                        Text("\(drafts.count) photo\(drafts.count == 1 ? "" : "s") selected")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if !drafts.isEmpty {
                    Section("Selected Photos") {
                        ForEach(Array(drafts.enumerated()), id: \.element.id) { index, draft in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text("Photo \(index + 1)")
                                        .font(.headline)
                                    Spacer()
                                    Button(role: .destructive) {
                                        removeDraft(at: index)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .accessibilityLabel("Remove photo")
                                }

                                if let previewImage = draft.previewImage {
                                    Image(uiImage: previewImage)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxHeight: 240)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                } else if isLoadingPreviews {
                                    ProgressView("Loading preview...")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    Text("Preview unavailable.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }

                                TextField(
                                    "Optional note",
                                    text: noteBinding(for: draft.id)
                                )
                                .textFieldStyle(.roundedBorder)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } else {
                    Section("Selected Photos") {
                        Text("Choose one or more photos to preview them here before importing.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Import Photo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isImporting ? "Saving..." : "Import") {
                        Task { await importSelectedPhotos() }
                    }
                    .disabled(drafts.isEmpty || isLoadingPreviews || isImporting)
                }
            }
            .task(id: selectedItems) {
                await rebuildDrafts()
            }
        }
    }

    private func noteBinding(for draftID: String) -> Binding<String> {
        Binding(
            get: {
                drafts.first(where: { $0.id == draftID })?.note ?? ""
            },
            set: { newValue in
                guard let index = drafts.firstIndex(where: { $0.id == draftID }) else { return }
                drafts[index].note = newValue
            }
        )
    }

    @MainActor
    private func rebuildDrafts() async {
        let previousDrafts = drafts
        let previousDraftsByID = Dictionary(uniqueKeysWithValues: previousDrafts.map { ($0.id, $0) })
        drafts = selectedItems.enumerated().map { index, item in
            let assetIdentifier = item.itemIdentifier
            let id = assetIdentifier ?? "selected-photo-\(index)"
            let previous = previousDraftsByID[id]
            return PhotoImportDraft(
                id: id,
                assetIdentifier: assetIdentifier,
                item: item,
                previewImage: previous?.previewImage,
                note: previous?.note ?? ""
            )
        }

        guard !drafts.isEmpty else {
            statusMessage = nil
            isLoadingPreviews = false
            return
        }

        isLoadingPreviews = true
        defer { isLoadingPreviews = false }

        var firstErrorMessage: String?
        for index in drafts.indices {
            if Task.isCancelled { return }
            do {
                let data = try await drafts[index].item.loadTransferable(type: Data.self)
                drafts[index].previewImage = data.flatMap(UIImage.init(data:))
            } catch {
                drafts[index].previewImage = nil
                if firstErrorMessage == nil {
                    firstErrorMessage = error.localizedDescription
                }
            }
        }

        statusMessage = firstErrorMessage
    }

    private func importSelectedPhotos() async {
        guard !drafts.isEmpty else { return }
        isImporting = true
        defer { isImporting = false }

        var importedResults: [ImportedPhotoImportResult] = []
        var failedCount = 0
        var firstErrorMessage: String?
        for draft in drafts {
            do {
                guard let assetIdentifier = draft.assetIdentifier, !assetIdentifier.isEmpty else {
                    throw TravelsError.photoImportFailed("Unable to retrieve photo metadata.")
                }
                let data = try await draft.item.loadTransferable(type: Data.self)
                guard let data else {
                    throw TravelsError.photoImportFailed("Unable to read image data.")
                }
                let imported = try model.importPhoto(
                    assetIdentifier: assetIdentifier,
                    data: data,
                    note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                importedResults.append(imported)
            } catch {
                failedCount += 1
                if firstErrorMessage == nil {
                    firstErrorMessage = error.localizedDescription
                }
            }
        }
        guard let earliest = importedResults.min(by: { $0.timestamp < $1.timestamp }) else {
            statusMessage = firstErrorMessage ?? "Unable to import photos."
            return
        }
        model.focusAfterImport(
            eventIDs: importedResults.map(\.eventID),
            timestamp: earliest.timestamp
        )
        if failedCount > 0 {
            model.statusMessage = "Imported \(importedResults.count) photo\(importedResults.count == 1 ? "" : "s"), skipped \(failedCount) that could not be imported."
        }
        dismiss()
    }

    private func removeDraft(at index: Int) {
        guard drafts.indices.contains(index), selectedItems.indices.contains(index) else { return }
        drafts.remove(at: index)
        selectedItems.remove(at: index)
    }
}

private struct PhotoImportDraft: Identifiable {
    let id: String
    let assetIdentifier: String?
    let item: PhotosPickerItem
    var previewImage: UIImage?
    var note: String
}
