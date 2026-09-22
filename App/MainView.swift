import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var paletteQuery = ""
    @State private var browseQuery = ""
    @State private var browseItems: [PaletteItem] = []
    @State private var active = false

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            if model.sidePane {
                SidePane(active: active)
                Divider()
            }
            VStack(spacing: 0) {
                TopRow(active: active)
                if let notice = model.storageNotice {
                    HStack {
                        Text(notice).font(.caption).foregroundStyle(.secondary)
                        Button("Dismiss") { model.storageNotice = nil }
                    }.padding(8)
                }
                if let error = model.storageError {
                    Text(error).font(.caption).foregroundStyle(.red).padding(8)
                }
                EditorView(editor: model.editor)
                    .overlay(alignment: .bottom) { bottomBar }
                    .overlay(alignment: .topTrailing) {
                        if model.overlay == .find {
                            FindBar(model: model).padding(12)
                        }
                    }
            }
            .frame(minWidth: model.chromeMetrics.minWidth)
        }
        // Over the whole window, so the palette is centered in it whether or not the pane is open. Before the
        // safe area is ignored below, so the reader's height is the window's, title bar included, which the
        // top-row floor counts on.
        .overlay {
            GeometryReader { geometry in
                palette
                    .padding(paletteInsets(in: geometry.size.height))
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        // The hidden title bar still reserves its height; the top row takes that space.
        .ignoresSafeArea(edges: .top)
        .frame(minHeight: 240)
        // The backdrop fills the title bar too; a background alone stops at the safe area in a hosting view.
        .background { WindowBackdrop(opacity: model.windowOpacity, tint: model.windowTint).ignoresSafeArea() }
        // Hidden, but the title is what accessibility and Mission Control call the window.
        .onChange(of: model.title, initial: true) { model.window?.title = model.title }
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
        .onChange(of: model.overlay) { _, _ in
            paletteQuery = ""
            browseQuery = ""
            browseItems = []
        }
        .disabled(model.convertingStorage)
        .overlay { if model.convertingStorage { ProgressView("Converting storage…").padding().background(.regularMaterial) } }
        .tint(model.accentColor)
        .environment(\.chrome, model.chromeMetrics)
    }

    private var bottomBar: some View {
        GlassEffectContainer {
            ZStack(alignment: .trailing) {
                if !model.formatBarHidden {
                    FormatBar(editor: model.editor)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, model.chromeMetrics.circleSize + 8)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { model.formatBarHidden.toggle() }
                } label: {
                    Image(systemName: model.formatBarHidden ? "textformat" : "xmark")
                        .font(.system(size: model.chromeMetrics.iconSize - 4, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: model.chromeMetrics.circleSize, height: model.chromeMetrics.circleSize)
                        .glassEffect(.regular, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.formatBarHidden ? "Show Formatting Bar" : "Hide Formatting Bar")
                .help(model.formatBarHidden ? "Show Formatting Bar" : "Hide Formatting Bar")
            }
            // A set height, not a minimum: the bar's own controls can ask for a point or two more than the
            // capsule draws, and the button, centered in whatever the tallest child is, would move with it.
            .frame(height: model.chromeMetrics.barHeight)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        // The bar stays while the window is not key, as its close does; the Aa alone goes with the actions.
        // Opacity goes on the container: the glass it draws for its children ignores theirs.
        .opacity(model.formatBarHidden && !active ? 0 : 1)
        .allowsHitTesting(!model.formatBarHidden || active)
        .animation(.easeOut(duration: 0.15), value: active)
    }

    // Set in from the sides and, at its tallest, centered a little above the middle of the window. The top is
    // where a full palette puts it and stays there as results come and go, so the field never moves under
    // the typing; a short window keeps the palette clear of the top row instead.
    private func paletteInsets(in height: CGFloat) -> EdgeInsets {
        let top = max(Chrome.rowHeight + 8, height * 0.4 - PaletteView.maxHeight / 2)
        return EdgeInsets(top: top, leading: 22, bottom: 16, trailing: 22)
    }

    @ViewBuilder private var palette: some View {
        switch model.overlay {
        case .palette:
            PaletteView(
                placeholder: "Search for actions…",
                items: model.filteredPaletteItems(paletteQuery),
                query: $paletteQuery,
                dismiss: model.dismissOverlay
            )
        case .browse:
            PaletteView(placeholder: "Search memos…", items: browseItems, query: $browseQuery, dismiss: model.dismissOverlay)
                .task(id: "\(model.storeGeneration) \(browseQuery)") { browseItems = await model.browseItems(browseQuery) }
        default:
            EmptyView()
        }
    }
}
