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
    /// Narrower and the bar's controls crop.
    static let minWidth: CGFloat = 400
}

/// What the menu bar item shows: the app's own mark, drawn as a template so the menu bar colors it, or
/// one of the system's symbols.
enum MenuBarIcon: String, CaseIterable, Identifiable {
    case squiggle, scribble, note, compose

    var id: String { rawValue }

    var title: String {
        switch self {
        case .squiggle: "Squiggle"
        case .scribble: "Scribble"
        case .note: "Note"
        case .compose: "Compose"
        }
    }

    /// nil for the app's own mark, which is an asset rather than a symbol.
    var systemImage: String? {
        switch self {
        case .squiggle: nil
        case .scribble: "scribble"
        case .note: "note.text"
        case .compose: "square.and.pencil"
        }
    }

    static let asset = "MenuBarIcon"
}

/// The memo's text size, in points. The stylesheet's own default is Medium's.
enum TextSize: Double, CaseIterable, Identifiable {
    case small = 13, medium = 15, large = 17

    var id: Double { rawValue }
    var points: Double { rawValue }

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    /// The nearest size to a stored one, which may come from another version or an edited preference.
    init(nearest points: Double) {
        self = Self.allCases.min { abs($0.rawValue - points) < abs($1.rawValue - points) } ?? .medium
    }
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

    /// The formatting bar's buttons take the menus' glyphs, which need the extra couple of points.
    var barButtonHeight: CGFloat { buttonHeight + 2 }

    static let compact = ChromeMetrics(
        pillHeight: 30, iconSize: 15, buttonWidth: 28, buttonHeight: 24, circleSize: 30, barHeight: 32
    )
    static let standard = ChromeMetrics(
        pillHeight: 34, iconSize: 17, buttonWidth: 32, buttonHeight: 28, circleSize: 34, barHeight: 36
    )
}

extension EnvironmentValues {
    @Entry var chrome: ChromeMetrics = .compact
}
