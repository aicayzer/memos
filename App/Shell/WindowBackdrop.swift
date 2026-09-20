import SwiftUI

/// Glass under the whole window, with the plain window color laid over it at the chosen opacity.
struct WindowBackdrop: View {
    let opacity: Double

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color(nsColor: .windowBackgroundColor).opacity(opacity)
        }
        .ignoresSafeArea()
    }
}
