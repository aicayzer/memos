import Foundation
import OSLog
import WebKit

private let log = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "editor")

/// Serves the memo's images to the page under a scheme of its own, so the editor is given the bytes it
/// needs and no access to the disk. Only a path the image store wrote is answered.
@MainActor
final class ImageSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "memo-image"
    /// The host is a constant: the page's images all come from the one store.
    static func url(for path: String) -> String { "\(scheme)://memo/\(path)" }

    private let images: any ImageStore
    /// A task that has been stopped must not be replied to, and there is no way to ask whether it has.
    private var live: Set<ObjectIdentifier> = []

    init(images: any ImageStore) {
        self.images = images
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        let id = ObjectIdentifier(task)
        live.insert(id)
        let path = (task.request.url?.path(percentEncoded: false)).map { String($0.dropFirst()) } ?? ""
        Task {
            let data = await images.url(for: path).flatMap { try? Data(contentsOf: $0) }
            guard live.contains(id) else { return }
            live.remove(id)
            guard let data, let type = ImageType(sniffing: data), let url = task.request.url else {
                log.error("image not served")
                task.didFailWithError(URLError(.fileDoesNotExist))
                return
            }
            let response = URLResponse(url: url, mimeType: type.mimeType, expectedContentLength: data.count, textEncodingName: nil)
            task.didReceive(response)
            task.didReceive(data)
            task.didFinish()
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        live.remove(ObjectIdentifier(task))
    }
}
