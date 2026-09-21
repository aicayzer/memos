import AppKit
import SwiftUI

/// Records one key for an in-app shortcut. KeyboardShortcuts' recorder is for global hotkeys: it refuses
/// any key the menu already uses, and here the menu's own keys are what is being changed. The event is
/// taken by a local monitor, ahead of the menu, so pressing ⌘N records rather than making a memo.
struct KeyRecorder: View {
    let key: KeyCombo?
    /// The other shortcuts that share this key, when any do.
    let conflict: String?
    var recordsOnAppear = false
    let onRecord: (KeyCombo?) -> Void
    var onCancel: () -> Void = {}

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            if recording {
                Text("Type a shortcut")
                    .foregroundStyle(.secondary)
            } else if let key {
                ForEach(Array(key.label.enumerated()), id: \.offset) { _, glyph in
                    Text(String(glyph))
                        .frame(minWidth: 16, minHeight: 16)
                        .background(.quaternary, in: .rect(cornerRadius: 3))
                }
                if let conflict {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.tint)
                        .help(conflict)
                        .accessibilityLabel(conflict)
                }
                Button { onRecord(nil) } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            } else {
                Text("Record Shortcut")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 6)
        .frame(height: 22)
        .background(.quinary, in: .rect(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(recording ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), lineWidth: recording ? 2 : 1)
        }
        .contentShape(.rect)
        .onTapGesture { recording ? cancel() : start() }
        .onAppear { if recordsOnAppear { start() } }
        .onDisappear(perform: stop)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(recording ? "Recording" : key?.label ?? "Record Shortcut")
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handle(event) }
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        guard let pressed = KeyCombo(event: event) else { return }
        if pressed == KeyCombo("Escape", []) { return cancel() }
        if pressed == KeyCombo("Backspace", []) {
            stop()
            return onRecord(nil)
        }
        guard pressed.isShortcut else { return }
        stop()
        onRecord(pressed)
    }

    private func cancel() {
        stop()
        onCancel()
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
