import AppKit
import UniformTypeIdentifiers

/// A stored image, read to be saved under a name of the person's choosing.
struct ImageExport {
    enum Failure: Error { case unavailable }

    let data: Data
    let type: ImageType

    static func load(_ reference: String, from images: any ImageStore) async throws -> ImageExport {
        guard ImageReference.isOurs(reference), let url = await images.url(for: reference) else { throw Failure.unavailable }
        let data = try Data(contentsOf: url)
        guard let type = ImageType(sniffing: data) else { throw Failure.unavailable }
        return ImageExport(data: data, type: type)
    }

    var suggestedName: String { "Image.\(type.fileExtension)" }

    var contentType: UTType { UTType(filenameExtension: type.fileExtension) ?? .image }

    /// The save panel has already confirmed any replacement, so the file is swapped in whole or not at all.
    func write(to destination: URL) throws {
        try data.write(to: destination, options: .atomic)
    }
}

/// What the person is offered on an image: the web view's own items, Download Image among them, do nothing here.
enum ImageMenu {
    static let saveTitle = "Save Image…"

    /// Nil for a reference the store did not write, so there is nothing to offer.
    static func make(for reference: String, target: AnyObject, action: Selector) -> NSMenu? {
        guard ImageReference.isOurs(reference) else { return nil }
        let menu = NSMenu()
        let item = NSMenuItem(title: saveTitle, action: action, keyEquivalent: "")
        item.target = target
        item.representedObject = reference
        menu.addItem(item)
        return menu
    }
}
