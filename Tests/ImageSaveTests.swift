import AppKit
import Testing
@testable import Memos

@MainActor
@Suite struct ImageSaveTests {
    private let picture = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data((0..<64).map { UInt8($0) })

    private func store(in folder: URL) -> FolderImageStore {
        FolderImageStore(besideStoreAt: folder.appending(path: "store.json"))
    }

    @Test func theMessageCarriesTheReferenceAndThePointInThePage() throws {
        let reference = "images/\(String(repeating: "a", count: 64)).png"
        let message = try #require(EditorMessage(body: ["type": "imageMenu", "reference": reference, "x": 12.5, "y": 40]))
        guard case .imageMenu(let decoded, let point) = message else { Issue.record("not an image menu"); return }
        #expect(decoded == reference)
        #expect(point == CGPoint(x: 12.5, y: 40))
        #expect(EditorMessage(body: ["type": "imageMenu", "x": 1, "y": 1]) == nil)
        #expect(EditorMessage(body: ["type": "imageMenu", "reference": reference, "x": 1]) == nil)
    }

    @Test func theMenuOffersOnlySaveImage() throws {
        let target = NSObject()
        let reference = "images/\(String(repeating: "b", count: 64)).png"
        let menu = try #require(ImageMenu.make(for: reference, target: target, action: #selector(NSObject.isEqual(_:))))
        #expect(menu.items.map(\.title) == ["Save Image…"])
        #expect(menu.items.first?.representedObject as? String == reference)
        #expect(menu.items.first?.target === target)
    }

    @Test func noMenuIsOfferedForAReferenceTheStoreDidNotWrite() {
        for reference in ["images/shot.png", "https://example.com/a.png", "images/../secret.png", ""] {
            #expect(ImageMenu.make(for: reference, target: NSObject(), action: #selector(NSObject.isEqual(_:))) == nil)
        }
    }

    @Test func aStoredImageIsSavedWithItsOwnBytesAndATypedName() async throws {
        let folder = try temporaryFolder()
        defer { discard(folder) }
        let images = store(in: folder)
        let reference = try await images.save(picture).path
        let image = try await ImageExport.load(reference, from: images)
        #expect(image.suggestedName == "Image.png")
        #expect(image.contentType.conforms(to: .png))
        let destination = folder.appending(path: "Saved.png")
        try image.write(to: destination)
        #expect(try Data(contentsOf: destination) == picture)
    }

    @Test func saveReplacesAFileTheSavePanelHasAlreadyConfirmed() async throws {
        let folder = try temporaryFolder()
        defer { discard(folder) }
        let images = store(in: folder)
        let reference = try await images.save(picture).path
        let destination = folder.appending(path: "Saved.png")
        try Data("old".utf8).write(to: destination)
        let editor = EditorController(images: images)
        var warnings: [String] = []
        editor.onWarning = { warnings.append($0) }
        await editor.saveImage(reference) { _ in destination }
        #expect(warnings.isEmpty)
        #expect(try Data(contentsOf: destination) == picture)
    }

    @Test func cancellingTheSavePanelWritesNothing() async throws {
        let folder = try temporaryFolder()
        defer { discard(folder) }
        let images = store(in: folder)
        let reference = try await images.save(picture).path
        let editor = EditorController(images: images)
        var warnings: [String] = []
        editor.onWarning = { warnings.append($0) }
        await editor.saveImage(reference) { _ in nil }
        #expect(warnings.isEmpty)
    }

    @Test func aReferenceThatFailsValidationWarnsAndWritesNothing() async throws {
        let folder = try temporaryFolder()
        defer { discard(folder) }
        let images = store(in: folder)
        let editor = EditorController(images: images)
        var warnings: [String] = []
        editor.onWarning = { warnings.append($0) }
        let destination = folder.appending(path: "Saved.png")
        var asked = false
        await editor.saveImage("images/../store.json") { _ in asked = true; return destination }
        #expect(warnings == ["Couldn’t save the image."])
        #expect(!asked)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func anImageThatIsNoLongerStoredWarnsAndWritesNothing() async throws {
        let folder = try temporaryFolder()
        defer { discard(folder) }
        let editor = EditorController(images: store(in: folder))
        var warnings: [String] = []
        editor.onWarning = { warnings.append($0) }
        let destination = folder.appending(path: "Saved.png")
        var asked = false
        await editor.saveImage("images/\(String(repeating: "c", count: 64)).png") { _ in asked = true; return destination }
        #expect(warnings == ["Couldn’t save the image."])
        #expect(!asked)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func aFailedWriteWarnsAndLeavesTheExistingFileAlone() async throws {
        let folder = try temporaryFolder()
        defer { discard(folder) }
        let images = store(in: folder)
        let reference = try await images.save(picture).path
        let editor = EditorController(images: images)
        var warnings: [String] = []
        editor.onWarning = { warnings.append($0) }
        let destination = folder.appending(path: "Missing/Saved.png")
        await editor.saveImage(reference) { _ in destination }
        #expect(warnings == ["Couldn’t save the image."])
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}
