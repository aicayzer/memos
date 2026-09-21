import SwiftUI

struct WindowBackdrop: View {
    let opacity: Double
    let tint: NSColor?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Glass()
            Color(nsColor: tint ?? Self.baseColor(for: colorScheme)).opacity(opacity)
        }
        .clipShape(.rect(cornerRadius: Chrome.cornerRadius))
    }

    // Black rather than the system window color, so the blur's own tint comes through.
    static func baseColor(for scheme: ColorScheme) -> NSColor {
        scheme == .dark ? .black : .white
    }

    // SwiftUI materials go flat while the window is inactive, which for a floating window is most of the time.
    private struct Glass: NSViewRepresentable {
        func makeNSView(context: Context) -> NSVisualEffectView {
            let view = NSVisualEffectView()
            view.material = .underWindowBackground
            view.blendingMode = .behindWindow
            view.state = .active
            // The blur is shaped by its own mask; a clip on the hosting layer does not reach it.
            let radius = Chrome.cornerRadius
            let side = radius * 2 + 1
            let mask = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
                NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
                return true
            }
            mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
            mask.resizingMode = .stretch
            view.maskImage = mask
            return view
        }

        func updateNSView(_ view: NSVisualEffectView, context: Context) {}
    }
}
