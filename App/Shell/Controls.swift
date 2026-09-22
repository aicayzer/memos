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
    static let cornerRadius: CGFloat = 22
    static let paneWidth: CGFloat = 220
    static let paneRoom = paneWidth + 1
}

/// The size of the app's own controls: the title bar's actions, the formatting bar and the two glass
/// circles. Compact is what the window is drawn for; standard matches a toolbar's own buttons, which
/// the title bar's fixed height still has room for.
struct ChromeMetrics: Equatable {
    let pillHeight: CGFloat
    let iconSize: CGFloat
    let buttonWidth: CGFloat
    let buttonHeight: CGFloat
    let circleSize: CGFloat
    let barHeight: CGFloat
    /// Narrower and the formatting bar's controls crop.
    let minWidth: CGFloat

    /// The formatting bar's buttons take the menus' glyphs, which need the extra couple of points.
    var barButtonHeight: CGFloat { buttonHeight + 2 }

    static let compact = ChromeMetrics(
        pillHeight: 30, iconSize: 15, buttonWidth: 28, buttonHeight: 24, circleSize: 30, barHeight: 32,
        minWidth: 400
    )
    static let standard = ChromeMetrics(
        pillHeight: 34, iconSize: 17, buttonWidth: 32, buttonHeight: 28, circleSize: 34, barHeight: 36,
        minWidth: 440
    )
}

extension EnvironmentValues {
    @Entry var chrome: ChromeMetrics = .compact
}
