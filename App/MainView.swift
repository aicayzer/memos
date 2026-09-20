import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var paletteQuery = ""
    @State private var browseQuery = ""
    @State private var browseItems: [PaletteItem] = []

    var body: some View {
        @Bindable var model = model
        EditorView(controller: model.editor)
            .background(WindowReader { model.attach($0) })
            .navigationTitle(model.title)
            .toolbarTitleDisplayMode(.inline)
            .task { await model.start() }
            .onAppear { model.openMainWindow = { openWindow(id: "main") } }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
                guard (note.object as? NSWindow) === model.window else { return }
                Task { await model.flush() }
            }
            .overlay(alignment: .bottom) {
                if !model.formatBarHidden {
                    FormatBar(editor: model.editor)
                        .padding(.bottom, 12)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !model.formatBarHidden {
                    Button {
                        model.formatBarHidden = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .glassEffect(.regular, in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hide Formatting Bar")
                    .help("Hide Formatting Bar")
                    .padding(12)
                }
            }
            .overlay(alignment: .topTrailing) {
                if model.overlay == .find {
                    FindBar(model: model).padding(12)
                }
            }
            .overlay(alignment: .top) {
                switch model.overlay {
                case .palette:
                    PaletteView(
                        placeholder: "Search for actions",
                        items: model.filteredPaletteItems(paletteQuery),
                        query: $paletteQuery,
                        dismiss: model.dismissOverlay
                    )
                    .padding(.top, 24)
                    .padding(.horizontal, 16)
                case .browse:
                    PaletteView(placeholder: "Search memos", items: browseItems, query: $browseQuery, dismiss: model.dismissOverlay)
                        .padding(.top, 24)
                        .padding(.horizontal, 16)
                        .task(id: browseQuery) { browseItems = await model.browseItems(browseQuery) }
                default:
                    EmptyView()
                }
            }
            .onChange(of: model.overlay) { _, overlay in
                paletteQuery = ""
                browseQuery = ""
                if overlay == nil { model.findText = "" }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { model.toggle(.palette) } label: { Label("Command Palette", systemImage: "command") }
                    Button { model.toggle(.browse) } label: { Label("Browse Memos", systemImage: "square.stack") }
                    Button { Task { await model.newMemo() } } label: { Label("New Memo", systemImage: "plus") }
                }
            }
    }
}
