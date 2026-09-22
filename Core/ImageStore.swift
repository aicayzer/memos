import CryptoKit
import Foundation

/// The types an image is kept in. Anything else a memo is given is converted to one of them first.
enum ImageType: String, CaseIterable, Sendable {
    case png, jpeg, gif, webp

    var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .gif: "gif"
        case .webp: "webp"
        }
    }

    var mimeType: String { "image/\(rawValue)" }

    static func named(_ fileExtension: String) -> ImageType? {
        let name = fileExtension.lowercased()
        if name == "jpg" { return .jpeg }
        return allCases.first { $0.rawValue == name }
    }

    /// What the bytes themselves say they are; the name a file arrived under is not trusted.
    init?(sniffing data: Data) {
        let bytes = [UInt8](data.prefix(16))
        func matches(_ signature: [UInt8?], at offset: Int) -> Bool {
            guard bytes.count >= offset + signature.count else { return false }
            return signature.enumerated().allSatisfy { $0.element == nil || bytes[offset + $0.offset] == $0.element }
        }
        if matches([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], at: 0) { self = .png }
        else if matches([0xFF, 0xD8, 0xFF], at: 0) { self = .jpeg }
        else if matches([0x47, 0x49, 0x46, 0x38], at: 0) { self = .gif }
        else if matches([0x52, 0x49, 0x46, 0x46], at: 0), matches([0x57, 0x45, 0x42, 0x50], at: 8) { self = .webp }
        else { return nil }
    }
}

/// An image as a memo refers to it: a path under the images folder, relative to the store file, which is
/// what the markdown carries and what an export copies.
struct ImageReference: Hashable, Sendable {
    let path: String
    /// What to call it in the alt text; the file name says nothing, so it is usually empty.
    var alt = ""

    /// The folder every reference sits in, beside the store file. Lower case, so the reference and the
    /// folder are the same word wherever the memo is read.
    static let folder = "images"

    /// Only a path this store wrote: the hash, a known extension, and nowhere else on the disk.
    static func isOurs(_ path: String) -> Bool {
        guard path.hasPrefix("\(folder)/") else { return false }
        let name = String(path.dropFirst(folder.count + 1))
        let parts = name.split(separator: ".", maxSplits: 1)
        guard parts.count == 2, parts[0].count == 64,
              parts[0].allSatisfy({ $0.isHexDigit && ($0.isNumber || $0.isLowercase) }),
              ImageType.named(String(parts[1])) != nil else { return false }
        return true
    }

    /// Every image this store holds that the markdown refers to.
    static func references(in markdown: String) -> Set<String> {
        let inMarkdown = /!\[[^\]]*\]\(\s*<?([^)>\s]+)>?[^)]*\)/
        return Set(markdown.matches(of: inMarkdown).map { String($0.1) }.filter(isOurs))
    }
}

enum ImageStoreError: LocalizedError {
    case unsupported

    var errorDescription: String? {
        switch self {
        case .unsupported: "That is not an image Memos can keep."
        }
    }
}

protocol ImageStore: Sendable {
    /// Keeps the bytes under their own hash and returns what a memo refers to them by. Bytes already held
    /// are not written again.
    func save(_ data: Data) async throws -> ImageReference
    /// Where a referenced image sits, or nil when the reference is not this store's.
    func url(for path: String) async -> URL?
    /// Removes every image none of the memos refers to.
    func removeOrphans(keeping used: Set<String>) async
}

/// A folder beside the store file, one file per image, named for the SHA-256 of its bytes. Nothing in it
/// ever changes, so it needs no lock: a name that is there is the image it names.
actor FolderImageStore: ImageStore {
    let folder: URL

    /// Beside the store file, as the memos' relative paths read it.
    init(besideStoreAt storeURL: URL) {
        folder = storeURL.deletingLastPathComponent().appending(path: ImageReference.folder)
    }

    func save(_ data: Data) throws -> ImageReference {
        guard let type = ImageType(sniffing: data) else { throw ImageStoreError.unsupported }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let name = "\(digest).\(type.fileExtension)"
        let url = folder.appending(path: name)
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        return ImageReference(path: "\(ImageReference.folder)/\(name)")
    }

    func url(for path: String) -> URL? {
        guard ImageReference.isOurs(path) else { return nil }
        return folder.appending(path: String(path.dropFirst(ImageReference.folder.count + 1)))
    }

    func removeOrphans(keeping used: Set<String>) {
        let names = Set(used.map { String($0.dropFirst(ImageReference.folder.count + 1)) })
        let held = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in held where !names.contains(name) {
            try? FileManager.default.removeItem(at: folder.appending(path: name))
        }
    }
}

/// Removes the images no memo refers to. The app and the command line tool both delete memos, so both
/// sweep; `alsoKeeping` covers an edit that has not reached the store yet.
enum ImageSweep {
    static func run(store: any MemoStore, images: any ImageStore, alsoKeeping unsaved: [String] = []) async {
        guard let memos = try? await store.list(matching: nil) else { return }
        var used: Set<String> = []
        for markdown in memos.map(\.markdown) + unsaved {
            used.formUnion(ImageReference.references(in: markdown))
        }
        await images.removeOrphans(keeping: used)
    }
}
