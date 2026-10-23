import SwiftUI

// HSplitView honors the bounds but distributes spare width on first layout. Set
// its initial divider once; subsequent resizing belongs to the native split view.
struct SidebarInitialWidth: NSViewRepresentable {
    let width: CGFloat

    func makeNSView(context: Context) -> Reader {
        Reader(width: width)
    }

    func updateNSView(_ view: Reader, context: Context) {}

    final class Reader: NSView {
        private let width: CGFloat
        private var positioned = false

        init(width: CGFloat) {
            self.width = width
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, !positioned else { return }
            positioned = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                var parent = self.superview
                while let ancestor = parent {
                    if let split = ancestor as? NSSplitView {
                        split.layoutSubtreeIfNeeded()
                        split.setPosition(self.width, ofDividerAt: 0)
                        return
                    }
                    parent = ancestor.superview
                }
            }
        }
    }
}
