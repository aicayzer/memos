import SwiftUI

struct WindowBackdrop: View {
    let opacity: Double
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Glass()
            // Black rather than the system window color, so the blur's own tint comes through.
            (colorScheme == .dark ? Color.black : Color.white).opacity(opacity)
        }
    }

    // SwiftUI materials go flat while the window is inactive, which for a floating window is most of the time.
    private struct Glass: NSViewRepresentable {
        func makeNSView(context: Context) -> NSVisualEffectView {
            let view = NSVisualEffectView()
            view.material = .underWindowBackground
            view.blendingMode = .behindWindow
            view.state = .active
            return view
        }

        func updateNSView(_ view: NSVisualEffectView, context: Context) {}
    }
}
