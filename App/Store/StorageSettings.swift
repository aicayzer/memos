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
        panel.message = "Locate the Memos folder shown in Storage settings."
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
            storageNotice = "Storage converted and verified. The previous files are kept as a recovery snapshot."
            didConvertStorage()
        } catch { storageError = error.localizedDescription }
    }
}

struct StorageSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Toggle("Store memos as Markdown files", isOn: Binding(
                    get: { model.storageStatus?.markdown ?? false },
                    set: { enabled in Task { await model.setMarkdownStorage(enabled) } }
                ))
                .disabled(model.convertingStorage || model.storageStatus == nil)
                if model.convertingStorage {
                    ProgressView("Converting and verifying memos…")
                }
                if let status = model.storageStatus {
                    LabeledContent("Location") {
                        Text(status.location.path).textSelection(.enabled).lineLimit(3).truncationMode(.middle)
                    }
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([status.location]) }
                    if let recovery = status.recovery {
                        Button("Show Previous Storage") { NSWorkspace.shared.activateFileViewerSelecting([recovery]) }
                    }
                }
            } footer: {
                Text("Switching converts all existing memos, including their images, favorites and dates. Only the selected format stays active. Previous files are retained for recovery; edits to those copies do not appear here.")
            }
            if let error = model.storageError {
                Section {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                    if model.storageStatus?.markdown == true {
                        Button("Locate Markdown Folder…") { Task { await model.locateMarkdownFolder() } }
                    }
                }
            }
            if let notice = model.storageNotice {
                Section { Text(notice).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .task { await model.refreshStorage() }
    }
}
