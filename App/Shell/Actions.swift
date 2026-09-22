import Foundation

extension AppModel {
    /// Grouped by what they act on. Nothing is hidden when it cannot be run, so the order never moves
    /// under the hands; a query drops the groups it empties and leaves the rest labeled.
    var paletteItems: [PaletteItem] {
        [
            PaletteItem(id: "new", title: "New Memo", symbol: "plus", shortcut: shortcuts.label(.newMemo), section: "Memo") {
                Task { await self.newMemo() }
            },
            PaletteItem(
                id: "duplicate", title: "Duplicate Memo", symbol: "plus.square.on.square",
                shortcut: shortcuts.label(.duplicate), section: "Memo"
            ) {
                Task { await self.duplicate() }
            },
            PaletteItem(id: "delete", title: "Delete Memo", symbol: "trash", shortcut: shortcuts.label(.delete), section: "Memo") {
                Task { await self.deleteMemo() }
            },
            PaletteItem(
                id: "favorite", title: current?.favorite == true ? "Unfavorite Memo" : "Favorite Memo",
                symbol: current?.favorite == true ? "star.slash" : "star", shortcut: shortcuts.label(.favorite), section: "Memo"
            ) {
                Task { await self.toggleFavorite() }
            },
            PaletteItem(
                id: "browse", title: "Browse Memos", symbol: "square.stack",
                shortcut: shortcuts.label(.browse), section: "Navigate"
            ) {
                self.toggle(.browse)
            },
            PaletteItem(
                id: "back", title: "Go Back", symbol: "arrow.left.circle", shortcut: shortcuts.label(.back),
                section: "Navigate", enabled: history.canGoBack
            ) {
                Task { await self.goBack() }
            },
            PaletteItem(
                id: "forward", title: "Go Forward", symbol: "arrow.right.circle", shortcut: shortcuts.label(.forward),
                section: "Navigate", enabled: history.canGoForward
            ) {
                Task { await self.goForward() }
            },
            PaletteItem(
                id: "find", title: "Find in Memo", symbol: "text.magnifyingglass",
                shortcut: shortcuts.label(.find), section: "Text"
            ) {
                self.toggle(.find)
            },
            PaletteItem(
                id: "formatBar", title: formatBarHidden ? "Show Formatting Bar" : "Hide Formatting Bar",
                symbol: "textformat", section: "Text"
            ) {
                self.formatBarHidden.toggle()
            },
            PaletteItem(
                id: "copy", title: "Copy as Markdown", symbol: "doc.on.clipboard",
                shortcut: shortcuts.label(.copyMarkdown), section: "Export"
            ) {
                self.copyAsMarkdown()
            },
            PaletteItem(
                id: "saveAs", title: "Save As…", symbol: "square.and.arrow.down",
                shortcut: shortcuts.label(.saveAs), section: "Export"
            ) {
                Task { await self.saveAs() }
            },
            PaletteItem(id: "share", title: "Share…", symbol: "square.and.arrow.up", section: "Export") {
                Task { await self.share() }
            },
            PaletteItem(
                id: "float", title: floating ? "Turn Off Always on Top" : "Turn On Always on Top",
                symbol: floating ? "pin.slash.fill" : "macwindow.on.rectangle", section: "Window"
            ) {
                self.floating.toggle()
            },
            PaletteItem(
                id: "sidePane", title: sidePane ? "Hide Side Pane" : "Show Side Pane",
                symbol: "sidebar.left", shortcut: shortcuts.label(.sidePane), section: "Window"
            ) {
                self.toggleSidePane()
            },
            PaletteItem(id: "settings", title: "Settings…", symbol: "gearshape", shortcut: "⌘,", section: "Window") {
                self.showSettings()
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
                symbol: memo.favorite ? "star.fill" : "doc.text",
                accented: memo.favorite
            ) {
                Task { await self.open(memo.id) }
            }
        }
    }
}
