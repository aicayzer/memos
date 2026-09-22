import Foundation

/// Folder notifications miss in-place writes by ordinary editors. A content revision also catches those,
/// and follows the committed storage location without keeping a watch on a retired snapshot.
@MainActor
final class LibraryWatcher {
    private var task: Task<Void, Never>?

    init(store: LibraryStore, onChange: @escaping @MainActor () -> Void, onError: @escaping @MainActor (String) -> Void) {
        task = Task {
            var previous: String?
            var lastError: String?
            while !Task.isCancelled {
                do {
                    let revision = try await store.revision()
                    if let previous, previous != revision { onChange() }
                    previous = revision
                    lastError = nil
                } catch {
                    if error.localizedDescription != lastError { onError(error.localizedDescription) }
                    lastError = error.localizedDescription
                }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    deinit { task?.cancel() }
}
