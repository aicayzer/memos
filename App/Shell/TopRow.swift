import SwiftUI

/// The title bar's content: a centered title and, while the window is key, the three actions.
struct TopRow: View {
    @Environment(AppModel.self) private var model
    let active: Bool

    var body: some View {
        ZStack {
            Text(model.title)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 120)
            HStack(spacing: 2) {
                action("command", "Command Palette") { model.toggle(.palette) }
                action("square.stack", "Browse Memos") { model.toggle(.browse) }
                action("plus", "New Memo") { Task { await model.newMemo() } }
            }
            .padding(.horizontal, 4)
            .frame(height: Chrome.pillHeight)
            .glassEffect(.regular, in: .capsule)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(active ? 1 : 0)
            .allowsHitTesting(active)
            .animation(.easeOut(duration: 0.15), value: active)
        }
        .frame(height: Chrome.rowHeight)
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .gesture(WindowDragGesture())
        .onTapGesture(count: 2) { model.window?.performTitleBarDoubleClick() }
    }

    private func action(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HoverHighlight {
                Image(systemName: symbol)
                    .font(.system(size: Chrome.iconSize, weight: .medium))
                    .frame(width: 28, height: 24)
            }
        }
        .buttonStyle(.borderless)
        .tint(.primary)
        .accessibilityLabel(label)
        .help(label)
    }
}

extension NSWindow {
    /// What System Settings says a double-click on the title bar does.
    func performTitleBarDoubleClick() {
        let action = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleActionOnDoubleClick"]
        switch action as? String {
        case "Minimize": performMiniaturize(nil)
        case "None": break
        default: performZoom(nil)
        }
    }
}
