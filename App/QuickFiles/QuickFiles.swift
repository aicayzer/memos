import AppKit
import Darwin
import KeyboardShortcuts
import Observation
import SwiftUI
import UniformTypeIdentifiers

enum QuickFileFormat: String, CaseIterable, Identifiable {
    case txt, md

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

enum QuickFileError: LocalizedError {
    case unsupported
    case encoding
    case changed
    case missingFolder

    var errorDescription: String? {
        switch self {
        case .unsupported: "Choose a .txt or .md file."
        case .encoding: "This file is not UTF-8 text. It was not changed."
        case .changed: "The file changed outside Memos. Use Save As to keep both versions."
        case .missingFolder: "The chosen folder is unavailable. Select it again in Quick Files settings."
        }
    }
}

@MainActor
@Observable
final class QuickFiles {
    var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: Self.enabledKey)
            updateShortcut()
        }
    }
    var format: QuickFileFormat {
        didSet { defaults.set(format.rawValue, forKey: Self.formatKey) }
    }
    private(set) var folder: URL
    private(set) var url: URL?
    var text = ""
    private(set) var savedText = ""
    var isActive = false
    var error: String?
    var notice: String?
    private var baseline: Data?
    private var documentScope: URL?
    private var folderScope: URL?
    private var panel: QuickFilePanel?
    private var shortcutInstalled = false
    private let defaults: UserDefaults
    private let memoModel: AppModel
    private let presentsWindow: Bool
    private let copyPath: @MainActor (String) -> Void

    private static let enabledKey = "quickFiles.enabled"
    private static let formatKey = "quickFiles.format"
    private static let folderBookmarkKey = "quickFiles.folderBookmark"

    private static var downloadsFolder: URL {
        // FileManager's Downloads URL is redirected into a sandbox container even with Downloads access.
        guard let record = getpwuid(getuid()), let home = String(validatingCString: record.pointee.pw_dir) else {
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        }
        return URL(fileURLWithPath: home, isDirectory: true).appending(path: "Downloads", directoryHint: .isDirectory)
    }

    init(memoModel: AppModel, defaults: UserDefaults = .standard,
         defaultFolder: URL? = nil, presentsWindow: Bool = true,
         copyPath: @escaping @MainActor (String) -> Void = {
             NSPasteboard.general.clearContents()
             NSPasteboard.general.setString($0, forType: .string)
         }) {
        self.memoModel = memoModel
        self.defaults = defaults
        self.presentsWindow = presentsWindow
        self.copyPath = copyPath
        enabled = defaults.bool(forKey: Self.enabledKey)
        format = defaults.string(forKey: Self.formatKey).flatMap(QuickFileFormat.init(rawValue:)) ?? .txt
        folder = defaultFolder ?? Self.downloadsFolder
        var stale = false
        if let data = defaults.data(forKey: Self.folderBookmarkKey),
           let resolved = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) {
            folder = resolved
            folderScope = resolved.startAccessingSecurityScopedResource() ? resolved : nil
        }
    }

    var isDirty: Bool { text != savedText }
    var isVisible: Bool { panel?.isVisible == true }
    var isDefaultFolder: Bool { defaults.data(forKey: Self.folderBookmarkKey) == nil }

    func installShortcut() {
        KeyboardShortcuts.onKeyDown(for: .quickFile) { [weak self] in self?.newFile() }
        shortcutInstalled = true
        updateShortcut()
    }

    private func updateShortcut() {
        guard shortcutInstalled else { return }
        if enabled {
            KeyboardShortcuts.enable(.quickFile)
        } else {
            KeyboardShortcuts.disable(.quickFile)
        }
    }

    func chooseFolder() async {
        let picker = NSOpenPanel()
        picker.canChooseFiles = false
        picker.canChooseDirectories = true
        picker.canCreateDirectories = true
        picker.prompt = "Use Folder"
        picker.directoryURL = folder
        guard await picker.begin() == .OK, let chosen = picker.url else { return }
        do {
            let data = try chosen.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            folderScope?.stopAccessingSecurityScopedResource()
            defaults.set(data, forKey: Self.folderBookmarkKey)
            folder = chosen
            folderScope = chosen.startAccessingSecurityScopedResource() ? chosen : nil
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func useDownloads() {
        folderScope?.stopAccessingSecurityScopedResource()
        folderScope = nil
        defaults.removeObject(forKey: Self.folderBookmarkKey)
        folder = Self.downloadsFolder
        error = nil
    }

    func newFile() {
        guard enabled, confirmDiscard() else { return }
        documentScope?.stopAccessingSecurityScopedResource()
        documentScope = nil
        url = nil
        baseline = nil
        text = ""
        savedText = ""
        error = nil
        notice = nil
        show()
    }

    func openPicker() async {
        guard enabled, confirmDiscard() else { return }
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        picker.allowsOtherFileTypes = false
        guard await picker.begin() == .OK, let chosen = picker.url else { return }
        open(chosen, alreadyConfirmed: true)
    }

    func open(_ file: URL, alreadyConfirmed: Bool = false) {
        if !enabled {
            guard presentsWindow else { return }
            let alert = NSAlert()
            alert.messageText = "Quick Files is turned off"
            alert.informativeText = "Enable Quick Files to edit this document in Memos."
            alert.addButton(withTitle: "Enable Quick Files")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            enabled = true
        }
        guard alreadyConfirmed || confirmDiscard() else { return }
        guard ["txt", "md"].contains(file.pathExtension.lowercased()) else {
            error = QuickFileError.unsupported.localizedDescription
            show()
            return
        }
        let accessing = file.startAccessingSecurityScopedResource()
        do {
            let bytes = try Data(contentsOf: file)
            guard let content = String(data: bytes, encoding: .utf8) else { throw QuickFileError.encoding }
            documentScope?.stopAccessingSecurityScopedResource()
            documentScope = accessing ? file : nil
            url = file
            text = content
            savedText = content
            baseline = bytes
            error = nil
            notice = nil
            show()
        } catch {
            if accessing { file.stopAccessingSecurityScopedResource() }
            self.error = error.localizedDescription
            show()
        }
    }

    func save() {
        do {
            if let url {
                guard try Data(contentsOf: url) == baseline else { throw QuickFileError.changed }
                let bytes = Data(text.utf8)
                try bytes.write(to: url, options: .atomic)
                baseline = bytes
                savedText = text
                notice = "Saved"
            } else {
                guard isDefaultFolder || folderScope != nil else { throw QuickFileError.missingFolder }
                let destination = Self.availableURL(in: folder, format: format)
                let bytes = Data(text.utf8)
                try bytes.write(to: destination, options: .withoutOverwriting)
                url = destination
                baseline = bytes
                savedText = text
                if !isDefaultFolder {
                    documentScope = folder.startAccessingSecurityScopedResource() ? folder : nil
                }
                copyPath(destination.path)
                notice = "Saved and copied path"
            }
            error = nil
        } catch { self.error = error.localizedDescription; notice = nil }
    }

    func saveAs() async {
        let picker = NSSavePanel()
        picker.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        picker.directoryURL = url?.deletingLastPathComponent() ?? folder
        picker.nameFieldStringValue = url?.lastPathComponent ?? Self.suggestedName(format: format)
        guard await picker.begin() == .OK, let destination = picker.url else { return }
        let accessing = destination.startAccessingSecurityScopedResource()
        do {
            if destination.standardizedFileURL == url?.standardizedFileURL,
               try Data(contentsOf: destination) != baseline {
                throw QuickFileError.changed
            }
            let bytes = Data(text.utf8)
            try bytes.write(to: destination, options: .atomic)
            documentScope?.stopAccessingSecurityScopedResource()
            documentScope = accessing ? destination : nil
            url = destination
            baseline = bytes
            savedText = text
            error = nil
            notice = "Saved"
        } catch {
            if accessing { destination.stopAccessingSecurityScopedResource() }
            self.error = error.localizedDescription
        }
    }

    func share() {
        guard let url, !isDirty else {
            error = "Save the file before sharing it."
            return
        }
        guard let view = panel?.contentView else { return }
        NSSharingServicePicker(items: [url]).show(relativeTo: .zero, of: view, preferredEdge: .minY)
    }

    func saveToMemos() async {
        let content = text
        do {
            let memo = try await memoModel.store.create(markdown: content)
            if presentsWindow { await memoModel.open(memo.id) }
            notice = "Saved to Memos"
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func close() {
        guard confirmDiscard() else { return }
        text = savedText
        isActive = false
        panel?.orderOut(nil)
    }

    func canTerminate() -> Bool { confirmDiscard() }

    func expand() { panel?.zoom(nil) }

    private func show() {
        guard presentsWindow else { return }
        if panel == nil { panel = QuickFilePanel(files: self) }
        panel?.title = url?.lastPathComponent ?? "Untitled"
        panel?.center()
        isActive = true
        panel?.makeKeyAndOrderFront(nil)
    }

    private func confirmDiscard() -> Bool {
        guard isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Discard unsaved changes?"
        alert.informativeText = "Your changes to this quick file have not been saved."
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: "Discard Changes")
        return alert.runModal() == .alertSecondButtonReturn
    }

    static func suggestedName(format: QuickFileFormat, now: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "\(formatter.string(from: now)).\(format.rawValue)"
    }

    static func availableURL(in folder: URL, format: QuickFileFormat, now: Date = .now) -> URL {
        let name = suggestedName(format: format, now: now)
        let stem = String(name.dropLast(format.rawValue.count + 1))
        var candidate = folder.appending(path: name)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appending(path: "\(stem)-\(index).\(format.rawValue)")
            index += 1
        }
        return candidate
    }
}

private final class QuickFilePanel: NSPanel {
    private let files: QuickFiles

    init(files: QuickFiles) {
        self.files = files
        super.init(contentRect: NSRect(x: 0, y: 0, width: 840, height: 540),
                   styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .floating
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        isOpaque = false
        backgroundColor = .clear
        isMovableByWindowBackground = true
        minSize = NSSize(width: 520, height: 320)
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        contentView = NSHostingView(rootView: QuickFileView(files: files))
        center()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.charactersIgnoringModifiers == "s", modifiers == .command {
            files.save()
            return true
        }
        if event.charactersIgnoringModifiers == "s", modifiers == [.command, .shift] {
            Task { await files.saveAs() }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func close() { files.close() }

    override func becomeKey() {
        super.becomeKey()
        files.isActive = true
    }

}

private struct QuickFileView: View {
    @Bindable var files: QuickFiles
    @FocusState private var editing: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Button { files.close() } label: { Image(systemName: "xmark.circle.fill") }
                    .accessibilityLabel("Close Quick File")
                Button { files.expand() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .accessibilityLabel("Expand Quick File")
                Text(files.url?.lastPathComponent ?? "Untitled")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                if files.isDirty { Circle().frame(width: 6, height: 6).foregroundStyle(.secondary) }
                Spacer()
                Button { Task { await files.saveAs() } } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("Save As")
                Button { files.share() } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Share")
                Button { Task { await files.saveToMemos() } } label: { Image(systemName: "note.text.badge.plus") }
                    .accessibilityLabel("Save to Memos")
                Button("Save") { files.save() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .labelStyle(.iconOnly)
            .padding(.horizontal, 14)
            .frame(height: 42)

            VStack(spacing: 0) {
                TextEditor(text: $files.text)
                    .font(.system(size: 15))
                    .scrollContentBackground(.hidden)
                    .focused($editing)
                    .padding(10)
                if let error = files.error {
                    Text(error).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18).padding(.bottom, 8)
                } else if let notice = files.notice {
                    Text(notice).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18).padding(.bottom, 8)
                }
            }
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .padding([.horizontal, .bottom], 7)
        }
        // The title bar reserves a safe area even when its standard controls are hidden.
        .ignoresSafeArea(edges: .top)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .onAppear { editing = true }
    }
}

struct QuickFilesSettingsView: View {
    @Bindable var files: QuickFiles

    var body: some View {
        Form {
            Section {
                Toggle("Enable Quick Files", isOn: $files.enabled)
            } footer: {
                Text("Edit text files directly, separately from your Memos library.")
            }
            Section("Defaults") {
                LabeledContent("Save to") {
                    Text(files.isDefaultFolder ? "Downloads" : files.folder.path)
                        .lineLimit(1).truncationMode(.middle)
                    Button("Choose…") { Task { await files.chooseFolder() } }
                    if !files.isDefaultFolder { Button("Downloads") { files.useDownloads() } }
                }
                Picker("Format", selection: $files.format) {
                    ForEach(QuickFileFormat.allCases) { format in Text(format.title).tag(format) }
                }
                LabeledContent("New file shortcut") {
                    KeyboardShortcuts.Recorder(for: .quickFile)
                }
            }
            .disabled(!files.enabled)
            if let error = files.error { Text(error).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
