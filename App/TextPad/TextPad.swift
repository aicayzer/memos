import AppKit
import Darwin
import KeyboardShortcuts
import Observation
import UniformTypeIdentifiers

enum TextPadFormat: String, CaseIterable, Identifiable {
    case txt, md

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

enum TextPadReuse: Int, CaseIterable, Identifiable {
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

enum TextPadError: LocalizedError {
    case unsupported
    case encoding
    case changed
    case missingFolder
    case invalidName
    case nameExists
    case renamePermission

    var errorDescription: String? {
        switch self {
        case .unsupported: "Choose a .txt or .md file."
        case .encoding: "This file is not UTF-8 text. It was not changed."
        case .changed: "The file changed outside Memos. Use Save As to keep both versions."
        case .missingFolder: "The chosen folder is unavailable. Select it again in TextPad settings."
        case .invalidName: "Enter a filename without slashes, colons, or control characters. The name cannot be empty, . or .., or longer than 255 bytes including its extension."
        case .nameExists: "A file with that name already exists. Choose another name."
        case .renamePermission: "Memos cannot rename this file in its folder. Use Save As to choose a new name and keep the original."
        }
    }
}

@MainActor
@Observable
final class TextPad {
    var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: Self.enabledKey)
            updateShortcut()
        }
    }
    var format: TextPadFormat {
        didSet {
            defaults.set(format.rawValue, forKey: Self.formatKey)
            updateTitle()
        }
    }
    var saveAutomatically: Bool {
        didSet { defaults.set(saveAutomatically, forKey: Self.autoSaveKey) }
    }
    var reusePeriod: TextPadReuse {
        didSet { defaults.set(reusePeriod.rawValue, forKey: Self.reuseKey) }
    }
    var nameParts: [TextPadNamePart] {
        didSet {
            if let data = try? JSONEncoder().encode(nameParts) { defaults.set(data, forKey: Self.namePartsKey) }
        }
    }
    private(set) var folder: URL
    private(set) var url: URL?
    private(set) var documentID = UUID()
    var text = ""
    private(set) var savedText = ""
    var isActive = false
    var error: String?
    var notice: String?
    private var baseline: Data?
    private var documentScope: URL?
    private var folderScope: URL?
    private var panel: TextPadPanel?
    private var shortcutInstalled = false
    private var createdAt: Date?
    private var openedFromDisk = false
    private var pendingName: String?
    private var nextNumber: Int
    private enum Operation { case transition, filePanel, sharing, savingMemo }
    private var operation: Operation?
    private var sharePicker: NSSharingServicePicker?
    private var shareDelegate: TextPadSharePickerDelegate?
    private let defaults: UserDefaults
    private let memoModel: AppModel
    private let presentsWindow: Bool
    private let copyPath: @MainActor (String) -> Void
    private let selectOpenFile: @MainActor () async -> URL?
    private let selectSaveFile: @MainActor (URL, String) async -> URL?
    private let discardChanges: @MainActor () -> Bool

    private static let enabledKey = "textPad.enabled"
    private static let formatKey = "textPad.format"
    private static let folderBookmarkKey = "textPad.folderBookmark"
    private static let autoSaveKey = "textPad.saveAutomatically"
    private static let reuseKey = "textPad.reusePeriod"
    private static let namePartsKey = "textPad.nameParts"
    private static let nextNumberKey = "textPad.nextNumber"

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
         },
         selectOpenFile: (@MainActor () async -> URL?)? = nil,
         selectSaveFile: (@MainActor (URL, String) async -> URL?)? = nil,
         discardChanges: (@MainActor () -> Bool)? = nil) {
        self.memoModel = memoModel
        self.defaults = defaults
        self.presentsWindow = presentsWindow
        self.copyPath = copyPath
        self.selectOpenFile = selectOpenFile ?? Self.presentOpenPanel
        self.selectSaveFile = selectSaveFile ?? Self.presentSavePanel
        self.discardChanges = discardChanges ?? Self.confirmDiscard
        enabled = defaults.bool(forKey: Self.enabledKey)
        format = defaults.string(forKey: Self.formatKey).flatMap(TextPadFormat.init(rawValue:)) ?? .txt
        saveAutomatically = defaults.object(forKey: Self.autoSaveKey) as? Bool ?? true
        reusePeriod = TextPadReuse(rawValue: defaults.object(forKey: Self.reuseKey) as? Int ?? 15) ?? .fifteenMinutes
        nameParts = defaults.data(forKey: Self.namePartsKey)
            .flatMap { try? JSONDecoder().decode([TextPadNamePart].self, from: $0) } ?? TextPadFilename.defaultParts
        nextNumber = max(1, defaults.integer(forKey: Self.nextNumberKey))
        folder = defaultFolder ?? Self.downloadsFolder
        var stale = false
        if let data = defaults.data(forKey: Self.folderBookmarkKey),
           let resolved = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) {
            folder = resolved
            folderScope = resolved.startAccessingSecurityScopedResource() ? resolved : nil
        }
    }

    var isDirty: Bool { text != savedText }
    var isBusy: Bool { operation != nil }
    var isVisible: Bool { panel?.isVisible == true }
    var isDefaultFolder: Bool { defaults.data(forKey: Self.folderBookmarkKey) == nil }
    var editableName: String { url?.deletingPathExtension().lastPathComponent ?? pendingName ?? "" }
    var displayName: String {
        url?.lastPathComponent ?? pendingName.map { "\($0).\(format.rawValue)" } ?? "Untitled"
    }
    var namePreview: String {
        (try? TextPadFilename.name(parts: nameParts, format: format, number: nextNumber)) ?? "Invalid filename"
    }

    func installShortcut() {
        KeyboardShortcuts.onKeyDown(for: .textPad) { [weak self] in self?.toggle() }
        shortcutInstalled = true
        updateShortcut()
    }

    private func updateShortcut() {
        guard shortcutInstalled else { return }
        if enabled {
            KeyboardShortcuts.enable(.textPad)
        } else {
            KeyboardShortcuts.disable(.textPad)
        }
    }

    func chooseFolder() async {
        guard !isBusy else { return }
        operation = .filePanel
        defer { operation = nil }
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
        guard !isBusy else { return }
        folderScope?.stopAccessingSecurityScopedResource()
        folderScope = nil
        defaults.removeObject(forKey: Self.folderBookmarkKey)
        folder = Self.downloadsFolder
        error = nil
    }

    func newFile(now: Date = .now) {
        guard enabled, !isBusy else { return }
        operation = .transition
        defer { operation = nil }
        guard finishCurrent() else { return }
        resetDocument()
        createdAt = now
        show()
    }

    func toggle(now: Date = .now) {
        guard enabled, !isBusy else { return }
        if isVisible {
            close()
        } else if openedFromDisk || isReusable(at: now) {
            refreshCurrentFile()
            show()
        } else {
            newFile(now: now)
        }
    }

    func commandNew(now: Date = .now) {
        guard enabled, !isBusy else { return }
        if isReusable(at: now) {
            refreshCurrentFile()
            show()
        } else {
            newFile(now: now)
        }
    }

    private func isReusable(at now: Date) -> Bool {
        guard let createdAt, !openedFromDisk, reusePeriod != .alwaysNew else { return false }
        return now.timeIntervalSince(createdAt) < TimeInterval(reusePeriod.rawValue * 60)
    }

    private func resetDocument() {
        documentID = UUID()
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
        pendingName = nil
    }

    func openPicker() async {
        guard enabled, !isBusy else { return }
        operation = .filePanel
        defer { operation = nil }
        guard let chosen = await selectOpenFile() else { return }
        openDocument(chosen)
    }

    private static func presentOpenPanel() async -> URL? {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        picker.allowsOtherFileTypes = false
        guard await picker.begin() == .OK else { return nil }
        return picker.url
    }

    func open(_ file: URL) {
        guard !isBusy else { return }
        operation = .transition
        defer { operation = nil }
        openDocument(file)
    }

    private func openDocument(_ file: URL) {
        if !enabled {
            guard presentsWindow else { return }
            let alert = NSAlert()
            alert.messageText = "TextPad is turned off"
            alert.informativeText = "Enable TextPad to edit this document in Memos."
            alert.addButton(withTitle: "Enable TextPad")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            enabled = true
        }
        guard ["txt", "md"].contains(file.pathExtension.lowercased()) else {
            error = TextPadError.unsupported.localizedDescription
            show()
            return
        }
        if file.standardizedFileURL == url?.standardizedFileURL {
            refreshCurrentFile()
            show()
            return
        }
        let accessing = file.startAccessingSecurityScopedResource()
        do {
            let bytes = try Data(contentsOf: file)
            guard let content = String(data: bytes, encoding: .utf8) else { throw TextPadError.encoding }
            guard finishCurrent() else {
                if accessing { file.stopAccessingSecurityScopedResource() }
                return
            }
            documentScope?.stopAccessingSecurityScopedResource()
            documentScope = accessing ? file : nil
            documentID = UUID()
            url = file
            text = content
            savedText = content
            baseline = bytes
            createdAt = nil
            openedFromDisk = true
            pendingName = nil
            error = nil
            notice = nil
            show()
        } catch {
            if accessing { file.stopAccessingSecurityScopedResource() }
            self.error = error.localizedDescription
            show()
        }
    }

    private func refreshCurrentFile() {
        guard let url else { return }
        do {
            let bytes = try Data(contentsOf: url)
            guard let content = String(data: bytes, encoding: .utf8) else { throw TextPadError.encoding }
            if isDirty {
                guard bytes == baseline else { throw TextPadError.changed }
            } else {
                text = content
                savedText = content
                baseline = bytes
                notice = nil
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
            notice = nil
        }
    }

    func save() {
        guard !isBusy else { return }
        saveCurrent()
    }

    private func saveCurrent() {
        do {
            if let url {
                guard try Data(contentsOf: url) == baseline else { throw TextPadError.changed }
                let bytes = Data(text.utf8)
                try bytes.write(to: url, options: .atomic)
                baseline = bytes
                savedText = text
                notice = "Saved"
            } else {
                guard isDefaultFolder || folderScope != nil else { throw TextPadError.missingFolder }
                let bytes = Data(text.utf8)
                let destination: URL
                if let pendingName {
                    destination = folder.appending(path: try TextPadFilename.filename(stem: pendingName, extension: format.rawValue))
                    guard !FileManager.default.fileExists(atPath: destination.path) else { throw TextPadError.nameExists }
                    try bytes.write(to: destination, options: .withoutOverwriting)
                } else {
                    destination = try saveGeneratedFile(bytes)
                }
                url = destination
                pendingName = nil
                baseline = bytes
                savedText = text
                if !isDefaultFolder {
                    documentScope = folder.startAccessingSecurityScopedResource() ? folder : nil
                }
                copyPath(destination.path)
                notice = "Saved and copied path"
            }
            error = nil
            updateTitle()
        } catch { self.error = error.localizedDescription; notice = nil }
    }

    func saveAs() async {
        guard !isBusy else { return }
        operation = .filePanel
        defer { operation = nil }
        let content = text
        let directory = url?.deletingLastPathComponent() ?? folder
        let suggestion: (name: String, number: Int?)
        do {
            if let url { suggestion = (url.lastPathComponent, nil) }
            else if let pendingName {
                suggestion = (try TextPadFilename.filename(stem: pendingName, extension: format.rawValue), nil)
            } else {
                let generated = try TextPadFilename.available(in: directory, parts: nameParts,
                                                             format: format, number: nextNumber)
                guard generated.number < Int.max else { throw TextPadError.invalidName }
                suggestion = (generated.url.lastPathComponent, generated.number)
            }
        } catch {
            self.error = error.localizedDescription
            notice = nil
            return
        }
        guard let destination = await selectSaveFile(directory, suggestion.name) else { return }
        let accessing = destination.startAccessingSecurityScopedResource()
        do {
            if destination.standardizedFileURL == url?.standardizedFileURL,
               try Data(contentsOf: destination) != baseline {
                throw TextPadError.changed
            }
            let bytes = Data(content.utf8)
            try bytes.write(to: destination, options: .atomic)
            documentScope?.stopAccessingSecurityScopedResource()
            documentScope = accessing ? destination : nil
            url = destination
            pendingName = nil
            baseline = bytes
            savedText = content
            if let number = suggestion.number, destination.lastPathComponent == suggestion.name {
                advanceGeneratedNumber(after: number)
            }
            error = nil
            notice = "Saved"
            updateTitle()
        } catch {
            if accessing { destination.stopAccessingSecurityScopedResource() }
            self.error = error.localizedDescription
            notice = nil
        }
    }

    private static func presentSavePanel(directory: URL, name: String) async -> URL? {
        let picker = NSSavePanel()
        picker.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        picker.directoryURL = directory
        picker.nameFieldStringValue = name
        guard await picker.begin() == .OK else { return nil }
        return picker.url
    }

    func share(from anchor: NSView? = nil) {
        guard !isBusy, let view = anchor ?? panel?.contentView else { return }
        operation = .sharing
        do {
            let picker = NSSharingServicePicker(items: [try shareableURL()])
            let delegate = TextPadSharePickerDelegate { [weak self] in
                self?.operation = nil
                self?.sharePicker = nil
                self?.shareDelegate = nil
                if self?.panel?.isKeyWindow == false { self?.lostFocus() }
            }
            picker.delegate = delegate
            sharePicker = picker
            shareDelegate = delegate
            let rect = anchor == nil
                ? NSRect(x: view.bounds.maxX - 90, y: view.bounds.maxY - 38, width: 32, height: 24)
                : view.bounds
            picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
            error = nil
        } catch {
            operation = nil
            self.error = error.localizedDescription
        }
    }

    func shareableURL(in temporaryFolder: URL = FileManager.default.temporaryDirectory) throws -> URL {
        if let url, !isDirty, let current = try? Data(contentsOf: url), current == baseline { return url }
        let directory = temporaryFolder.appending(path: "TextPadShare-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name: String
        if let url { name = url.lastPathComponent }
        else if let pendingName { name = "\(pendingName).\(format.rawValue)" }
        else { name = try TextPadFilename.name(parts: nameParts, format: format, number: nextNumber) }
        let snapshot = directory.appending(path: name)
        try Data(text.utf8).write(to: snapshot, options: .atomic)
        return snapshot
    }

    func saveToMemos() async {
        guard !isBusy else { return }
        operation = .savingMemo
        defer { operation = nil }
        let content = text
        do {
            let memo = try await memoModel.store.create(markdown: content)
            if presentsWindow { await memoModel.open(memo.id) }
            notice = "Saved to Memos"
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func close() {
        guard !isBusy else { return }
        operation = .transition
        defer { operation = nil }
        guard finishCurrent() else { return }
        isActive = false
        panel?.orderOut(nil)
    }

    func lostFocus() {
        guard !isBusy, panel?.isVisible == true else { return }
        close()
    }

    private func finishCurrent() -> Bool {
        guard isDirty else { return true }
        if saveAutomatically {
            saveCurrent()
            return !isDirty
        }
        if url != nil {
            guard discardChanges() else { return false }
        }
        if url == nil { resetDocument() }
        else { text = savedText }
        return true
    }

    func canTerminate() -> Bool {
        guard !isBusy else { return false }
        operation = .transition
        defer { operation = nil }
        return finishCurrent()
    }

    func expand() { panel?.toggleExpanded() }

    @discardableResult
    func rename(to input: String) -> Bool {
        guard !isBusy else { return false }
        operation = .transition
        defer { operation = nil }
        do {
            let fileExtension = url?.pathExtension ?? format.rawValue
            let stem = try TextPadFilename.validatedStem(input)
            let name = try TextPadFilename.filename(stem: stem, extension: fileExtension)
            if let source = url {
                let destination = source.deletingLastPathComponent().appending(path: name)
                if destination != source {
                    guard canRenameInContainingFolder(source) else { throw TextPadError.renamePermission }
                    guard try Data(contentsOf: source) == baseline else { throw TextPadError.changed }
                    // Exclusive rename prevents an existing destination from being replaced, including races.
                    let result = source.withUnsafeFileSystemRepresentation { sourcePath in
                        destination.withUnsafeFileSystemRepresentation { destinationPath in
                            renameatx_np(AT_FDCWD, sourcePath!, AT_FDCWD, destinationPath!, UInt32(RENAME_EXCL))
                        }
                    }
                    guard result == 0 else {
                        switch errno {
                        case EEXIST: throw TextPadError.nameExists
                        case EACCES, EPERM: throw TextPadError.renamePermission
                        default: throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                        }
                    }
                    url = destination
                    if documentScope?.standardizedFileURL == source.standardizedFileURL {
                        documentScope?.stopAccessingSecurityScopedResource()
                        documentScope = nil
                    }
                }
            } else {
                pendingName = stem
            }
            error = nil
            notice = "Renamed"
            updateTitle()
            return true
        } catch {
            self.error = error.localizedDescription
            notice = nil
            return false
        }
    }

    private func canRenameInContainingFolder(_ source: URL) -> Bool {
        guard documentScope?.standardizedFileURL == source.standardizedFileURL else { return true }
        // A grant for one file does not authorize its new sibling name. Save As can request that grant.
        let directory = source.deletingLastPathComponent().resolvingSymlinksInPath().pathComponents
        let authorizedFolders = [Self.downloadsFolder, FileManager.default.temporaryDirectory] + [folderScope].compactMap { $0 }
        return authorizedFolders.contains { directory.starts(with: $0.resolvingSymlinksInPath().pathComponents) }
    }

    private func saveGeneratedFile(_ bytes: Data) throws -> URL {
        let now = Date.now
        while true {
            let candidate = try TextPadFilename.available(in: folder, parts: nameParts, format: format,
                                                         now: now, number: nextNumber)
            guard candidate.number < Int.max else { throw TextPadError.invalidName }
            do {
                try bytes.write(to: candidate.url, options: .withoutOverwriting)
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            }
            advanceGeneratedNumber(after: candidate.number)
            return candidate.url
        }
    }

    private func advanceGeneratedNumber(after number: Int) {
        nextNumber = max(number + 1, max(nextNumber, defaults.integer(forKey: Self.nextNumberKey)))
        defaults.set(nextNumber, forKey: Self.nextNumberKey)
    }

    private func updateTitle() {
        panel?.title = "TextPad: \(displayName)"
    }

    private func show() {
        guard presentsWindow else { return }
        if panel == nil { panel = TextPadPanel(files: self) }
        updateTitle()
        isActive = true
        panel?.makeKeyAndOrderFront(nil)
    }

    private static func confirmDiscard() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Discard unsaved changes?"
        alert.informativeText = "Your changes to this text file have not been saved."
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: "Discard Changes")
        return alert.runModal() == .alertSecondButtonReturn
    }
}

private final class TextPadSharePickerDelegate: NSObject, NSSharingServicePickerDelegate {
    let onDismiss: () -> Void

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        onDismiss()
    }
}
