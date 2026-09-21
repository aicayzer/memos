import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var hasShortcut = KeyboardShortcuts.getShortcut(for: .toggleWindow) != nil

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("Accent", selection: Binding(
                    get: { AccentChoice(model.accent) },
                    set: { choice in
                        switch choice {
                        case .standard: model.accent = .standard
                        case .system: model.accent = .system
                        case .custom: model.accent = .custom(Self.systemAccentSnapshot() ?? Accent.standardColor)
                        }
                    }
                )) {
                    Text("Default").tag(AccentChoice.standard)
                    Text("System").tag(AccentChoice.system)
                    Text("Custom").tag(AccentChoice.custom)
                }
                if case .custom(let color) = model.accent {
                    ColorPicker("Custom color", selection: Binding(
                        get: { Color(nsColor: color) },
                        set: { if let picked = Self.stored($0) { model.accent = .custom(picked) } }
                    ), supportsOpacity: false)
                }
                // Without a shortcut, the last way back to the window cannot be switched off.
                Toggle("Show in menu bar", isOn: $model.menuBarItem)
                    .disabled(model.menuBarItem && !model.showInDock && !hasShortcut)
                Toggle("Show in Dock", isOn: $model.showInDock)
                    .disabled(model.showInDock && !model.menuBarItem && !hasShortcut)
            } header: {
                Text("General")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if model.policyPending {
                        Text("The Dock changes when you switch to another app.")
                    }
                    if !model.menuBarItem, !model.showInDock {
                        Text("With both off, the keyboard shortcut still opens the window.")
                    } else if !hasShortcut, model.menuBarItem != model.showInDock {
                        Text("Set a shortcut to switch this off as well.")
                    }
                }
            }
            Section("Window") {
                Toggle("Always on top", isOn: $model.floating)
                Toggle("Side pane at launch", isOn: $model.sidePaneAtLaunch)
                LabeledContent("Background") {
                    // The slider draws its own value labels in the tint; beside it they stay secondary text.
                    HStack(spacing: 8) {
                        Text("Glass")
                        Slider(value: $model.windowOpacity, in: 0...1) { Text("Background") }
                            .labelsHidden()
                        Text("Solid")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                ColorPicker("Tint", selection: Binding(
                    get: { Color(nsColor: model.windowTint ?? WindowBackdrop.baseColor(for: colorScheme)) },
                    set: { picked in
                        // The well reports its own color when it opens; only a change is a tint.
                        guard let picked = Self.stored(picked), picked != model.windowTint,
                              picked != WindowBackdrop.baseColor(for: colorScheme) || model.windowTint != nil else { return }
                        model.windowTint = picked
                    }
                ), supportsOpacity: false)
                HStack {
                    Spacer()
                    Button("Reset Background") { model.resetBackground() }
                        .disabled(model.windowTint == nil && model.windowOpacity == AppModel.defaultWindowOpacity)
                }
            }
            Section("Shortcut") {
                KeyboardShortcuts.Recorder("Show or hide the window", name: .toggleWindow) { hasShortcut = $0 != nil }
            }
        }
        .formStyle(.grouped)
        .tint(model.accentColor)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        // Otherwise the always-on-top memo window covers it.
        .background(WindowReader { $0.level = .floating })
        // Opened from the panel while another app is in front, Settings would open behind it.
        .onAppear { NSApp.activate() }
    }

    private enum AccentChoice: Hashable {
        case standard, system, custom

        init(_ accent: Accent) {
            switch accent {
            case .standard: self = .standard
            case .system: self = .system
            case .custom: self = .custom
            }
        }
    }

    // What is kept is what is stored: 8-bit sRGB, opaque, so the window does not shift on relaunch.
    private static func stored(_ color: Color) -> NSColor? {
        NSColor(color).hexString.flatMap(NSColor.init(hexString:))
    }

    // A custom color starts as a frozen copy of the system accent, resolved in the current appearance.
    private static func systemAccentSnapshot() -> NSColor? {
        var color: NSColor?
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            color = NSColor.controlAccentColor.usingColorSpace(.sRGB)
        }
        return color
    }
}
