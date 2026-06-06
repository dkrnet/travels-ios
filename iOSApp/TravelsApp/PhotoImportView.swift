// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.

import PhotosUI
import SwiftUI
import UIKit

#if canImport(TravelsCore)
import TravelsCore
#endif

struct PhotoImportView: View {
    @EnvironmentObject private var model: TravelsModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var previewImage: UIImage?
    @State private var note = ""
    @State private var isLoading = false
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Photo") {
                    PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
                        Label("Choose Photo", systemImage: "photo.on.rectangle")
                    }
                    if let previewImage {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Text("Choose a photo to preview it here before importing.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Caption") {
                    TextField("Optional note", text: $note)
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
                    Button(isLoading ? "Saving..." : "Import") {
                        importSelectedPhoto()
                    }
                    .disabled(photoData == nil || isLoading)
                }
            }
            .task(id: selectedItem) {
                await loadSelectedPhoto()
            }
        }
    }

    private func loadSelectedPhoto() async {
        guard let selectedItem else {
            photoData = nil
            previewImage = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await selectedItem.loadTransferable(type: Data.self)
            photoData = data
            previewImage = data.flatMap(UIImage.init(data:))
            statusMessage = nil
        } catch {
            photoData = nil
            previewImage = nil
            statusMessage = error.localizedDescription
        }
    }

    private func importSelectedPhoto() {
        guard let data = photoData else { return }
        model.importPhoto(data: data, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}
