import AppKit
import KeyboardShortcuts
import SwiftUI

/// Records a shortcut in place: a click empties the box and the next chord typed fills it, a click elsewhere
/// leaves it empty, Escape brings the old one back. The chord is taken by a local monitor, ahead of the menu
/// and with the global hotkeys paused, so pressing ⌘N records rather than making a memo. One control serves
/// the app's shortcuts and the global hotkey; what each accepts is the caller's.
struct KeyRecorder: View {
    /// The shortcut as shown, nil when there is none.
    let label: String?
    /// The other shortcuts that share this key, when any do.
    let conflict: String?
    var recordsOnAppear = false
    /// Given each chord typed; true takes it as the shortcut, false keeps the box waiting.
    let onRecord: (NSEvent) -> Bool
    /// The box was left empty: the shortcut is gone.
    let onClear: () -> Void
    /// Escape, or the app going to the back: nothing changes.
    var onCancel: () -> Void = {}

    @State private var recording = false
    @State private var monitor: Any?
    @State private var anchor = Anchor()

    static let width: CGFloat = 120
    static let height: CGFloat = 22

    var body: some View {
        HStack(spacing: 6) {
            if let conflict, !recording {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.tint)
                    .help(conflict)
                    .accessibilityLabel(conflict)
            }
            Text(recording ? "Type a shortcut" : label ?? "")
                .foregroundStyle(recording ? .secondary : .primary)
                .lineLimit(1)
                .frame(width: Self.width, height: Self.height)
                .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(recording ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), lineWidth: recording ? 2 : 1)
                }
                .background(AnchorView(anchor: anchor))
                .contentShape(.rect)
                .onTapGesture { if !recording { start() } }
        }
        .onAppear { if recordsOnAppear { start() } }
        .onDisappear(perform: stop)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            if recording { cancel() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(recording ? "Recording" : label ?? "No shortcut")
    }

    private func start() {
        guard monitor == nil else { return }
        recording = true
        // A registered hotkey takes its key before any window sees it, so it could not be recorded again.
        KeyboardShortcuts.isEnabled = false
        // A click outside the box ends the recording with the box empty, rather than leaving it to swallow
        // keys meant for whatever was clicked; a click on the box itself changes nothing.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { event in
            let isKey = event.type == .keyDown
            MainActor.assumeIsolated {
                if isKey {
                    handle(event)
                } else if !anchor.contains(event) {
                    clear()
                }
            }
            return isKey ? nil : event
        }
    }

    private func handle(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        if event.keyCode == 53 { return cancel() }
        if event.modifierFlags.isDisjoint(with: [.command, .control, .option]),
           event.specialKey == .delete || event.specialKey == .deleteForward {
            return clear()
        }
        if onRecord(event) {
            stop()
        } else {
            NSSound.beep()
        }
    }

    private func clear() {
        stop()
        onClear()
    }

    private func cancel() {
        stop()
        onCancel()
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        KeyboardShortcuts.isEnabled = true
    }
}

/// Where the box is in its window, read from an empty view behind it, so a click can be told inside from
/// outside in the window's own coordinates.
@MainActor
private final class Anchor {
    weak var view: NSView?

    func contains(_ event: NSEvent) -> Bool {
        guard let view, event.window === view.window else { return false }
        return view.isMousePoint(view.convert(event.locationInWindow, from: nil), in: view.bounds)
    }
}

private struct AnchorView: NSViewRepresentable {
    let anchor: Anchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        anchor.view = view
    }
}
