import Foundation
import OSLog

private let log = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "store")

/// Wakes the app when the store's folder changes under it, as when the command line tool writes.
/// Its own writes fire too; the model tells them apart by what it finds.
final class StoreWatcher {
    private let source: DispatchSourceFileSystemObject?

    /// A folder that cannot be opened is not watched; the app still works, without live updates.
    init(directory: URL, onChange: @escaping @MainActor () -> Void) {
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            log.error("store folder not watched: \(String(cString: strerror(errno)), privacy: .public)")
            source = nil
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated(onChange) }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    deinit {
        source?.cancel()
    }
}
