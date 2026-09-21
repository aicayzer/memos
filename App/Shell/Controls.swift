import SwiftUI

/// Borderless controls show no hover on macOS; the glass chrome needs one. It wraps a
/// button's label rather than replacing the button style, which drops the accessibility name.
struct HoverHighlight<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @State private var hovering = false

    var body: some View {
        content()
            .background(.primary.opacity(hovering ? 0.08 : 0), in: .rect(cornerRadius: 6))
            .onHover { hovering = $0 }
    }
}

enum Chrome {
    static let rowHeight: CGFloat = 52
    static let pillHeight: CGFloat = 30
    static let barHeight: CGFloat = 32
    static let closeSize: CGFloat = 30
    static let iconSize: CGFloat = 15
    static let cornerRadius: CGFloat = 22
    static let paneWidth: CGFloat = 220
    /// The pane and its divider.
    static let paneRoom = paneWidth + 1
    /// Narrower and the bar's controls crop.
    static let minWidth: CGFloat = 400
}
