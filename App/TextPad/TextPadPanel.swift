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
    private let pendingTitleInput = OverlayInputResponder()

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(files: TextPad) {
        self.files = files
        super.init(contentRect: NSRect(x: 0, y: 0, width: 840, height: 540),
                   styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        #if DEBUG
        level = .normal
        #else
        level = .floating
        #endif
        isOpaque = false
        backgroundColor = .clear
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        // AppKit draws outside the window; a SwiftUI shadow gets clipped at the hosting bounds.
        hasShadow = true
        isMovableByWindowBackground = true
        minSize = NSSize(width: 520, height: 320)
        contentView = NSHostingView(rootView: TextPadView(files: files, prepareTitleFocus: { [weak self] in
            guard let self else { return }
            pendingTitleInput.discardEvents()
            makeFirstResponder(pendingTitleInput)
        }))
        center()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.charactersIgnoringModifiers == "n", modifiers == .command {
            files.commandNew()
            return true
        }
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
        pendingTitleInput.discardEvents()
        files.isActive = false
        files.lostFocus()
    }

}

private struct TextPadView: View {
    @Bindable var files: TextPad
    let prepareTitleFocus: () -> Void
    @State private var renaming = false
    @State private var titleDraft = ""
    @State private var renamedDocument: UUID?
    @FocusState private var editing: Bool
    @State private var shareAnchor = TextPadShareAnchor()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button { files.close() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .frame(width: 22, height: 26)
                }
                .accessibilityLabel("Close TextPad")
                if renaming {
                    HStack(spacing: 2) {
                        OverlaySearchField(placeholder: "Name", text: $titleDraft, fontSize: 14,
                                           isCurrent: { renaming && files.isActive && renamedDocument == files.documentID },
                                           submit: {
                                               guard renamedDocument == files.documentID else { return }
                                               if files.rename(to: titleDraft) { finishRename() }
                                           }, dismiss: finishRename, blur: { renaming = false })
                        Text(".\(files.url?.pathExtension ?? files.format.rawValue)")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .frame(width: 220, height: 24)
                    .background(.background, in: RoundedRectangle(cornerRadius: 5))
                } else {
                    Text(files.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .help("Double-click to rename")
                        .onTapGesture(count: 2) {
                            editing = false
                            titleDraft = files.editableName
                            renamedDocument = files.documentID
                            prepareTitleFocus()
                            renaming = true
                        }
                        .simultaneousGesture(WindowDragGesture())
                }
                DevelopmentBadge()
                if files.isDirty { Circle().frame(width: 6, height: 6).foregroundStyle(.secondary) }
                Spacer()
                HStack(spacing: 2) {
                    actionIcon("square.and.arrow.up", label: "Share", verticalOffset: -1) {
                        files.share(from: shareAnchor.view)
                    }
                    .background(TextPadShareAnchorView(anchor: shareAnchor).allowsHitTesting(false))
                    actionIcon("note.text.badge.plus", label: "Save to Memos", verticalOffset: 1) {
                        Task { await files.saveToMemos() }
                    }
                }
                Button("Save") { files.save() }
                    .buttonStyle(TextPadToolbarButtonStyle(primary: true))
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
                    .simultaneousGesture(WindowDragGesture())
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
        // AppKit owns the outside shape, shadow and resize border as one native rounded frame.
        .glassEffect(.regular, in: .rect)
        .ignoresSafeArea()
        .disabled(files.isBusy)
        .defaultFocus($editing, true)
        .onChange(of: files.documentID) { finishRename() }
        .onChange(of: files.isActive) {
            if files.isActive {
                if !renaming { editing = true }
            } else {
                renaming = false
            }
        }
    }

    private func finishRename() {
        renaming = false
        editing = files.isActive
    }

    private func actionIcon(_ symbol: String, label: String, verticalOffset: CGFloat,
                            perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .frame(width: 16)
                .offset(y: verticalOffset)
        }
        .buttonStyle(TextPadToolbarButtonStyle())
        .accessibilityLabel(label)
        .help(label)
    }
}

private struct TextPadToolbarButtonStyle: ButtonStyle {
    var primary = false
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(primary ? .primary : .secondary)
            .frame(height: 16)
            .padding(.horizontal, primary ? 14 : 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(primary || hovered || configuration.isPressed ? 0.1 : 0), in: Capsule())
            .contentShape(Capsule())
            .onHover { hovered = $0 }
    }
}
