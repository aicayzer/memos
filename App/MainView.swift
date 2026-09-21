import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var paletteQuery = ""
    @State private var browseQuery = ""
    @State private var browseItems: [PaletteItem] = []
    @State private var active = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            TopRow(active: active)
            EditorView(controller: model.editor)
                .overlay(alignment: .bottom) { bottomBar }
                .overlay(alignment: .topTrailing) {
                    if model.overlay == .find {
                        FindBar(model: model).padding(12)
                    }
                }
                .overlay(alignment: .top) { palette }
        }
        // The hidden title bar still reserves its height; the top row takes that space.
        .ignoresSafeArea(edges: .top)
        .background(WindowReader { model.attach($0) })
        .containerBackground(for: .window) { WindowBackdrop(opacity: model.windowOpacity) }
        .navigationTitle(model.title)
        .task { await model.start() }
        .onAppear { model.openMainWindow = { openWindow(id: "main") } }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            guard (note.object as? NSWindow) === model.window else { return }
            Task { await model.flush() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if (note.object as? NSWindow) === model.window { active = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
            guard (note.object as? NSWindow) === model.window else { return }
            active = false
            // A palette left open in a window that lost focus would still take the next keystrokes.
            if model.overlay == .palette || model.overlay == .browse { model.overlay = nil }
        }
        .onChange(of: model.overlay) { _, overlay in
            paletteQuery = ""
            browseQuery = ""
            browseItems = []
            if overlay == nil { model.findText = "" }
        }
        .tint(model.accentColor)
    }

    private var bottomBar: some View {
        GlassEffectContainer {
            ZStack(alignment: .trailing) {
                if !model.formatBarHidden {
                    FormatBar(editor: model.editor)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, Chrome.closeSize + 8)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { model.formatBarHidden.toggle() }
                } label: {
                    Image(systemName: model.formatBarHidden ? "textformat" : "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: Chrome.closeSize, height: Chrome.closeSize)
                        .glassEffect(.regular, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.formatBarHidden ? "Show Formatting Bar" : "Hide Formatting Bar")
                .help(model.formatBarHidden ? "Show Formatting Bar" : "Hide Formatting Bar")
            }
            // A fixed height, or the corner button sits a point lower whenever the taller bar is gone.
            .frame(maxWidth: .infinity, minHeight: Chrome.barHeight, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        // The bar stays while the window is not key, as its close does; the Aa alone goes with the actions.
        // Opacity goes on the container: the glass it draws for its children ignores theirs.
        .opacity(model.formatBarHidden && !active ? 0 : 1)
        .allowsHitTesting(!model.formatBarHidden || active)
        .animation(.easeOut(duration: 0.15), value: active)
    }

    // Set in from the sides and down from the title, floating over the text rather than capping it.
    private let paletteInsets = EdgeInsets(top: 48, leading: 22, bottom: 16, trailing: 22)

    @ViewBuilder private var palette: some View {
        switch model.overlay {
        case .palette:
            PaletteView(
                placeholder: "Search for actions…",
                items: model.filteredPaletteItems(paletteQuery),
                query: $paletteQuery,
                dismiss: model.dismissOverlay
            )
            .padding(paletteInsets)
        case .browse:
            PaletteView(placeholder: "Search memos…", items: browseItems, query: $browseQuery, dismiss: model.dismissOverlay)
                .padding(paletteInsets)
                .task(id: browseQuery) { browseItems = await model.browseItems(browseQuery) }
        default:
            EmptyView()
        }
    }
}
