import Foundation

/// Wakes the app when the store's folder changes under it, as when the command line tool writes.
/// Its own writes fire too; the model tells them apart by what it finds.
final class StoreWatcher {
    private let source: DispatchSourceFileSystemObject

    init(directory: URL, onChange: @escaping @MainActor () -> Void) {
        let descriptor = open(directory.path, O_EVTONLY)
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated(onChange) }
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}
