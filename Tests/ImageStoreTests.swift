import Foundation
import Testing
@testable import Memos

@Suite struct ImageTypeTests {
    @Test func theBytesSayWhatTheyAre() {
        #expect(ImageType(sniffing: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) == .png)
        #expect(ImageType(sniffing: Data([0xFF, 0xD8, 0xFF, 0xE0])) == .jpeg)
        #expect(ImageType(sniffing: Data("GIF89a".utf8)) == .gif)
        #expect(ImageType(sniffing: Data("RIFF\u{0}\u{0}\u{0}\u{0}WEBP".utf8)) == .webp)
    }

    @Test func anythingElseIsNotAnImage() {
        #expect(ImageType(sniffing: Data("not an image".utf8)) == nil)
        #expect(ImageType(sniffing: Data()) == nil)
        // A TIFF is an image, but not one the store keeps as it stands.
        #expect(ImageType(sniffing: Data([0x49, 0x49, 0x2A, 0x00])) == nil)
    }
}

@Suite struct ImageReferenceTests {
    private let hash = String(repeating: "a", count: 64)

    @Test func onlyThisStoresOwnPathsAreTaken() {
        #expect(ImageReference.isOurs("images/\(hash).png"))
        #expect(ImageReference.isOurs("images/\(hash).jpg"))
        #expect(!ImageReference.isOurs("images/../../secrets.png"))
        #expect(!ImageReference.isOurs("images/shot.png"))
        #expect(!ImageReference.isOurs("https://example.com/shot.png"))
        #expect(!ImageReference.isOurs("images/\(hash).exe"))
        #expect(!ImageReference.isOurs("images/\(String(repeating: "A", count: 64)).png"))
    }

    @Test func referencesAreReadOutOfTheMarkdown() {
        let markdown = """
        # A memo

        ![](images/\(hash).png)
        ![Sized|400](images/\(hash).jpg)
        ![Elsewhere](https://example.com/shot.png)
        [Not an image](images/\(hash).gif)
        """
        #expect(ImageReference.references(in: markdown) == ["images/\(hash).png", "images/\(hash).jpg"])
    }
}

@Suite struct FolderImageStoreTests {
    private func store() -> (FolderImageStore, URL) {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (FolderImageStore(besideStoreAt: folder.appending(path: "store.json")), folder)
    }

    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x2A])

    @Test func theSameBytesAreKeptOnce() async throws {
        let (images, folder) = store()
        let first = try await images.save(png)
        let second = try await images.save(png)
        #expect(first.path == second.path)
        let held = try FileManager.default.contentsOfDirectory(atPath: folder.appending(path: "images").path)
        #expect(held.count == 1)
        #expect(first.path.hasPrefix("images/"))
        #expect(first.path.hasSuffix(".png"))
    }

    @Test func whatIsNotAnImageIsRefused() async {
        let (images, _) = store()
        await #expect(throws: ImageStoreError.self) { try await images.save(Data("plain text".utf8)) }
    }

    @Test func anImageNoMemoRefersToGoes() async throws {
        let (images, _) = store()
        let kept = try await images.save(png)
        let dropped = try await images.save(Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01]))
        await images.removeOrphans(keeping: [kept.path])
        #expect(await images.url(for: kept.path).map { FileManager.default.fileExists(atPath: $0.path) } == true)
        #expect(await images.url(for: dropped.path).map { FileManager.default.fileExists(atPath: $0.path) } == false)
    }

    @Test func aPathFromSomewhereElseHasNoPlaceInTheFolder() async {
        let (images, _) = store()
        #expect(await images.url(for: "images/../store.json") == nil)
        #expect(await images.url(for: "/etc/passwd") == nil)
    }
}
