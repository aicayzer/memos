import AppKit
import SwiftUI

@MainActor
private final class TextPadShareAnchor {
    weak var view: NSView?
}

private struct TextPadShareAnchorView: NSViewRepresentable {
    let anchor: TextPadShareAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        anchor.view = view
    }
}

final class TextPadPanel: NSPanel {
    private let files: TextPad
    private var previousFrame: NSRect?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(files: TextPad) {
        self.files = files
        super.init(contentRect: NSRect(x: 0, y: 0, width: 840, height: 540),
                   styleMask: [.resizable, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = true
        minSize = NSSize(width: 520, height: 320)
        contentView = NSHostingView(rootView: TextPadView(files: files))
        center()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.charactersIgnoringModifiers == "s", modifiers == .command {
            files.save()
            return true
        }
        if event.charactersIgnoringModifiers == "s", modifiers == [.command, .shift] {
            Task { await files.saveAs() }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func close() { files.close() }

    func toggleExpanded() {
        if let previousFrame {
            setFrame(previousFrame, display: true, animate: true)
            self.previousFrame = nil
        } else if let screen = screen ?? NSScreen.main {
            previousFrame = frame
            setFrame(screen.visibleFrame.insetBy(dx: 24, dy: 24), display: true, animate: true)
        }
    }

    override func becomeKey() {
        super.becomeKey()
        files.isActive = true
    }

    override func resignKey() {
        super.resignKey()
        files.lostFocus()
    }

}

private struct TextPadView: View {
    @Bindable var files: TextPad
    @FocusState private var editing: Bool
    @State private var hoveredAction: Action?
    @State private var shareAnchor = TextPadShareAnchor()

    private enum Action: Hashable { case share, saveToMemos }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button { files.close() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .frame(width: 22, height: 26)
                }
                .accessibilityLabel("Close TextPad")
                Text(files.url?.lastPathComponent ?? "Untitled")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .onTapGesture(count: 2) { files.expand() }
                if files.isDirty { Circle().frame(width: 6, height: 6).foregroundStyle(.secondary) }
                Spacer()
                actionIcon("square.and.arrow.up", label: "Share", action: .share) {
                    files.share(from: shareAnchor.view)
                }
                .background(TextPadShareAnchorView(anchor: shareAnchor).allowsHitTesting(false))
                actionIcon("note.text.badge.plus", label: "Save to Memos", action: .saveToMemos) {
                    Task { await files.saveToMemos() }
                }
                Button("Save") { files.save() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .frame(height: 24)
                    .background(Color.primary.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .labelStyle(.iconOnly)
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .frame(height: 38)
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { files.expand() }
            }

            VStack(spacing: 0) {
                TextEditor(text: $files.text)
                    .font(.system(size: 15))
                    .scrollContentBackground(.hidden)
                    .focused($editing)
                    .padding(10)
                if let error = files.error {
                    Text(error).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18).padding(.bottom, 8)
                } else if let notice = files.notice {
                    Text(notice).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18).padding(.bottom, 8)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .padding([.horizontal, .bottom], 7)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .padding(8)
        .onAppear { editing = true }
    }

    private func actionIcon(_ symbol: String, label: String, action: Action,
                            perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 32, height: 26)
                .contentShape(Rectangle())
        }
        .background {
            Capsule()
                .fill(hoveredAction == action ? Color.primary.opacity(0.09) : .clear)
        }
        .onHover { hoveredAction = $0 ? action : nil }
        .accessibilityLabel(label)
        .help(label)
    }
}
