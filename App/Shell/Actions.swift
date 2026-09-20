import Foundation
import OSLog

private let log = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "app")

extension AppModel {
    var paletteItems: [PaletteItem] {
        [
            PaletteItem(id: "new", title: "New Memo", symbol: "plus", shortcut: "⌘N") {
                Task { await self.newMemo() }
            },
            PaletteItem(id: "duplicate", title: "Duplicate Memo", symbol: "plus.square.on.square", shortcut: "⌘D") {
                Task { await self.duplicate() }
            },
            PaletteItem(
                id: "pin", title: current?.pinned == true ? "Unpin Memo" : "Pin Memo",
                symbol: current?.pinned == true ? "pin.slash" : "pin", shortcut: "⇧⌘P"
            ) {
                Task { await self.togglePin() }
            },
            PaletteItem(id: "browse", title: "Browse Memos", symbol: "square.stack", shortcut: "⌘P") {
                self.toggle(.browse)
            },
            PaletteItem(id: "back", title: "Go Back", symbol: "arrow.left.circle", shortcut: "⌘[") {
                Task { await self.goBack() }
            },
            PaletteItem(id: "forward", title: "Go Forward", symbol: "arrow.right.circle", shortcut: "⌘]") {
                Task { await self.goForward() }
            },
            PaletteItem(id: "find", title: "Find in Memo", symbol: "text.magnifyingglass", shortcut: "⌘F", section: 1) {
                self.toggle(.find)
            },
            PaletteItem(id: "copy", title: "Copy as Markdown", symbol: "doc.on.clipboard", shortcut: "⇧⌘C", section: 1) {
                self.copyAsMarkdown()
            },
            PaletteItem(
                id: "float", title: floating ? "Turn Off Always on Top" : "Turn On Always on Top",
                symbol: floating ? "pin.slash.fill" : "macwindow.on.rectangle", section: 1
            ) {
                self.floating.toggle()
            },
            PaletteItem(
                id: "formatBar", title: formatBarHidden ? "Show Formatting Bar" : "Hide Formatting Bar",
                symbol: "textformat", section: 1
            ) {
                self.formatBarHidden.toggle()
            },
        ]
    }

    func filteredPaletteItems(_ query: String) -> [PaletteItem] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return paletteItems }
        return paletteItems.filter { $0.title.localizedCaseInsensitiveContains(needle) }
    }

    func browseItems(_ query: String) async -> [PaletteItem] {
        do {
            return try await store.list(matching: query).map { memo in
                PaletteItem(
                    id: memo.id.uuidString,
                    title: memo.title,
                    subtitle: memo.updatedAt.formatted(.relative(presentation: .named)),
                    symbol: memo.pinned ? "pin.fill" : "doc.text"
                ) {
                    Task { await self.open(memo.id) }
                }
            }
        } catch {
            log.error("browse: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
