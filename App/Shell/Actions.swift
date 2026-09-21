import Foundation

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
            PaletteItem(id: "back", title: "Go Back", symbol: "arrow.left.circle", shortcut: "⌘[", enabled: history.canGoBack) {
                Task { await self.goBack() }
            },
            PaletteItem(id: "forward", title: "Go Forward", symbol: "arrow.right.circle", shortcut: "⌘]", enabled: history.canGoForward) {
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
            PaletteItem(
                id: "sidePane", title: sidePane ? "Hide Side Pane" : "Show Side Pane",
                symbol: "sidebar.left", shortcut: "⌃⌘S", section: 1
            ) {
                self.toggleSidePane()
            },
        ]
    }

    func filteredPaletteItems(_ query: String) -> [PaletteItem] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return paletteItems }
        return paletteItems.filter { $0.title.localizedCaseInsensitiveContains(needle) }
    }

    func browseItems(_ query: String) async -> [PaletteItem] {
        await memos(matching: query).map { memo in
            PaletteItem(
                id: memo.id.uuidString,
                title: memo.title,
                subtitle: memo.updatedAt.formatted(.relative(presentation: .named)),
                symbol: memo.pinned ? "pin.fill" : "doc.text"
            ) {
                Task { await self.open(memo.id) }
            }
        }
    }
}
