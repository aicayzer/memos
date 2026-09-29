import AppKit
import SwiftUI

extension AppModel {
    func refreshStorage() async {
        guard let library = store as? LibraryStore else { return }
        do { storageStatus = try await library.status() }
        catch {
            storageError = error.localizedDescription
            storageStatus = try? await library.storedStatus()
        }
    }

    func locateMarkdownFolder() async {
        guard let library = store as? LibraryStore, !convertingStorage else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "Locate your Markdown memos folder."
        guard await panel.begin() == .OK, let folder = panel.url else { return }
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        do {
            storageStatus = try await library.reconnect(to: folder)
            storageError = nil
            storeChanged()
        } catch { storageError = error.localizedDescription }
    }

    func setMarkdownStorage(_ enabled: Bool) async {
        guard !convertingStorage, let library = store as? LibraryStore else { return }
        convertingStorage = true
        defer { convertingStorage = false }
        var parent: URL?
        var bookmark: Data?
        var accessing = false
        if enabled {
            NSApp.activate()
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.prompt = "Choose Folder"
            panel.message = "Memos will create a new folder here and convert all your memos to Markdown files."
            guard await panel.begin() == .OK, let url = panel.url else { return }
            parent = url
            accessing = url.startAccessingSecurityScopedResource()
            do { bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) }
            catch { storageError = error.localizedDescription; if accessing { url.stopAccessingSecurityScopedResource() }; return }
        }
        defer { if accessing { parent?.stopAccessingSecurityScopedResource() } }
        guard await flush() else { return }
        storageError = nil
        do {
            storageStatus = try await library.convert(toMarkdown: enabled, parent: parent, bookmark: bookmark)
            storageNotice = "Storage updated and verified."
            didConvertStorage()
        } catch { storageError = error.localizedDescription }
    }
}

struct StorageSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingConversion = false
    @State private var requestedMarkdown = false

    var body: some View {
        Group {
            Section {
                Picker("Keep memos", selection: Binding(
                    get: { model.storageStatus?.markdown ?? false },
                    set: { enabled in
                        guard enabled != model.storageStatus?.markdown else { return }
                        requestedMarkdown = enabled
                        confirmingConversion = true
                    }
                )) {
                    Text("Inside Memos").tag(false)
                    Text("As Markdown files").tag(true)
                }
                .disabled(model.convertingStorage || model.storageStatus == nil)
                if model.convertingStorage {
                    ProgressView("Converting and verifying memos…")
                }
                if let status = model.storageStatus, status.markdown {
                    LabeledContent("Folder") {
                        Text(status.location.path).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
                    }
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([status.location]) }
                }
                if let error = model.storageError {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                    if model.storageStatus?.markdown == true {
                        Button("Locate Markdown Folder…") { Task { await model.locateMarkdownFolder() } }
                    }
                }
                if let notice = model.storageNotice {
                    Text(notice).foregroundStyle(.secondary)
                }
            } header: {
                Text("Memo Storage")
            } footer: {
                Text("Applies to the whole library. Changing storage converts and verifies all memos and keeps the previous storage for recovery.")
            }
            Section {
                Button("Show Previous Storage") {
                    guard let recovery = model.storageStatus?.recovery else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([recovery])
                }
                .disabled(model.storageStatus?.recovery == nil)
            } header: {
                Text("Recovery")
            } footer: {
                Text("Available after a storage conversion. This is a recovery copy, not an automatic backup.")
            }
        }
        .confirmationDialog("Change memo storage?", isPresented: $confirmingConversion, titleVisibility: .visible) {
            Button(requestedMarkdown ? "Use Markdown Files…" : "Keep Memos Internally") {
                let enabled = requestedMarkdown
                Task { await model.setMarkdownStorage(enabled) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(requestedMarkdown
                 ? "All memos and images will be converted to files. Previous storage is kept for recovery."
                 : "All memos and images will move into Memos. The Markdown folder is kept for recovery; edits there will no longer appear in Memos.")
        }
        .task { await model.refreshStorage() }
    }
}
