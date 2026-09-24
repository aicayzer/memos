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

enum QuickFileReuse: Int, CaseIterable, Identifiable {
    case alwaysNew = 0, fiveMinutes = 5, tenMinutes = 10, fifteenMinutes = 15, thirtyMinutes = 30, oneHour = 60

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .alwaysNew: "Always new"
        case .fiveMinutes: "5 minutes"
        case .tenMinutes: "10 minutes"
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        case .oneHour: "1 hour"
        }
    }
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
    var saveAutomatically: Bool {
        didSet { defaults.set(saveAutomatically, forKey: Self.autoSaveKey) }
    }
    var commandNReuse: QuickFileReuse {
        didSet { defaults.set(commandNReuse.rawValue, forKey: Self.reuseKey) }
    }
    private(set) var folder: URL
    private(set) var url: URL?
    var text = ""
    private(set) var savedText = ""
    var isActive = false
    var isExpanded = false
    var error: String?
    var notice: String?
    private var baseline: Data?
    private var documentScope: URL?
    private var folderScope: URL?
    private var panel: QuickFilePanel?
    private var shortcutInstalled = false
    private var createdAt: Date?
    private var openedFromDisk = false
    private var isPresentingFilePanel = false
    private var isDismissing = false
    private let defaults: UserDefaults
    private let memoModel: AppModel
    private let presentsWindow: Bool
    private let copyPath: @MainActor (String) -> Void

    private static let enabledKey = "quickFiles.enabled"
    private static let formatKey = "quickFiles.format"
    private static let folderBookmarkKey = "quickFiles.folderBookmark"
    private static let autoSaveKey = "quickFiles.saveAutomatically"
    private static let reuseKey = "quickFiles.commandNReuse"

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
        saveAutomatically = defaults.object(forKey: Self.autoSaveKey) as? Bool ?? true
        commandNReuse = QuickFileReuse(rawValue: defaults.object(forKey: Self.reuseKey) as? Int ?? 15) ?? .fifteenMinutes
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

    func newFile(now: Date = .now) {
        guard enabled, finishCurrent() else { return }
        resetDocument()
        createdAt = now
        show()
    }

    func commandNew(now: Date = .now) {
        guard enabled else { return }
        if let createdAt, !openedFromDisk, commandNReuse != .alwaysNew,
           now.timeIntervalSince(createdAt) < TimeInterval(commandNReuse.rawValue * 60) {
            show()
        } else {
            newFile(now: now)
        }
    }

    private func resetDocument() {
        documentScope?.stopAccessingSecurityScopedResource()
        documentScope = nil
        url = nil
        baseline = nil
        text = ""
        savedText = ""
        error = nil
        notice = nil
        createdAt = nil
        openedFromDisk = false
    }

    func openPicker() async {
        guard enabled else { return }
        isPresentingFilePanel = true
        defer { isPresentingFilePanel = false }
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        picker.allowsOtherFileTypes = false
        guard await picker.begin() == .OK, let chosen = picker.url else { return }
        open(chosen)
    }

    func open(_ file: URL) {
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
        guard ["txt", "md"].contains(file.pathExtension.lowercased()) else {
            error = QuickFileError.unsupported.localizedDescription
            show()
            return
        }
        if file.standardizedFileURL == url?.standardizedFileURL {
            show()
            return
        }
        let accessing = file.startAccessingSecurityScopedResource()
        do {
            let bytes = try Data(contentsOf: file)
            guard let content = String(data: bytes, encoding: .utf8) else { throw QuickFileError.encoding }
            guard finishCurrent() else {
                if accessing { file.stopAccessingSecurityScopedResource() }
                return
            }
            documentScope?.stopAccessingSecurityScopedResource()
            documentScope = accessing ? file : nil
            url = file
            text = content
            savedText = content
            baseline = bytes
            createdAt = nil
            openedFromDisk = true
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
        isPresentingFilePanel = true
        defer { isPresentingFilePanel = false }
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
        guard finishCurrent() else { return }
        isDismissing = true
        isActive = false
        panel?.orderOut(nil)
        isDismissing = false
    }

    func lostFocus() {
        guard !isDismissing, !isPresentingFilePanel, panel?.isVisible == true else { return }
        close()
        if panel?.isVisible == true { panel?.makeKeyAndOrderFront(nil) }
    }

    private func finishCurrent() -> Bool {
        guard isDirty else { return true }
        if saveAutomatically {
            save()
            return !isDirty
        }
        if openedFromDisk {
            guard confirmDiscard() else { return false }
        }
        if !openedFromDisk { resetDocument() }
        else { text = savedText }
        return true
    }

    func canTerminate() -> Bool { finishCurrent() }

    func expand() { panel?.toggleExpanded() }

    private func show() {
        guard presentsWindow else { return }
        if panel == nil { panel = QuickFilePanel(files: self) }
        panel?.title = "Quick File: \(url?.lastPathComponent ?? "Untitled")"
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
    private var previousFrame: NSRect?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(files: QuickFiles) {
        self.files = files
        super.init(contentRect: NSRect(x: 0, y: 0, width: 840, height: 540),
                   styleMask: [.resizable, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        isMovableByWindowBackground = true
        minSize = NSSize(width: 520, height: 320)
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

    func toggleExpanded() {
        if let previousFrame {
            setFrame(previousFrame, display: true, animate: true)
            self.previousFrame = nil
            files.isExpanded = false
        } else if let screen = screen ?? NSScreen.main {
            previousFrame = frame
            setFrame(screen.visibleFrame.insetBy(dx: 24, dy: 24), display: true, animate: true)
            files.isExpanded = true
        }
    }

    override func becomeKey() {
        super.becomeKey()
        files.isActive = true
    }

    override func resignKey() {
        super.resignKey()
        files.lostFocus()
    }

}

private struct QuickFileView: View {
    @Bindable var files: QuickFiles
    @FocusState private var editing: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    icon("xmark.circle.fill", label: "Close Quick File") { files.close() }
                    icon("arrow.up.right.circle.fill",
                         label: files.isExpanded ? "Shrink Quick File" : "Expand Quick File") { files.expand() }
                }
                Text(files.url?.lastPathComponent ?? "Untitled")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .onTapGesture(count: 2) { files.expand() }
                if files.isDirty { Circle().frame(width: 6, height: 6).foregroundStyle(.secondary) }
                Spacer()
                icon("square.and.pencil", label: "Save As") { Task { await files.saveAs() } }
                icon("square.and.arrow.up", label: "Share", yOffset: 1) { files.share() }
                icon("note.text.badge.plus", label: "Save to Memos") { Task { await files.saveToMemos() } }
                Button("Save") { files.save() }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .buttonBorderShape(.capsule)
            }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .labelStyle(.iconOnly)
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .frame(height: 38)
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { files.expand() }
            }

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
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .padding([.horizontal, .bottom], 7)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .onAppear { editing = true }
    }

    private func icon(_ symbol: String, label: String, yOffset: CGFloat = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .offset(y: yOffset)
                .frame(width: 24, height: 26)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
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
                Toggle("Save automatically", isOn: $files.saveAutomatically)
                Picker("Reuse with Command-N", selection: $files.commandNReuse) {
                    ForEach(QuickFileReuse.allCases) { choice in Text(choice.title).tag(choice) }
                }
                LabeledContent("New file shortcut") {
                    KeyboardShortcuts.Recorder(for: .quickFile)
                }
            }
            .disabled(!files.enabled)
            Section {
                Text("The global shortcut always starts a new file. Command-N reopens the current quick file during the chosen interval. With automatic saving off, an unsaved scratch file disappears when you click away; opened files ask before discarding edits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!files.enabled)
            if let error = files.error { Text(error).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
