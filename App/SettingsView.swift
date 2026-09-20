import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var hasShortcut = KeyboardShortcuts.getShortcut(for: .toggleWindow) != nil

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Shortcut") {
                KeyboardShortcuts.Recorder("Show or hide the window", name: .toggleWindow) { hasShortcut = $0 != nil }
            }
            Section("Window") {
                Toggle("Always on top", isOn: $model.floating)
                LabeledContent("Background") {
                    Slider(value: $model.windowOpacity, in: 0...1) {
                        Text("Background")
                    } minimumValueLabel: {
                        Text("Glass")
                    } maximumValueLabel: {
                        Text("Solid")
                    }
                    .labelsHidden()
                }
            }
            Section {
                // Without a shortcut, the last way back to the window cannot be switched off.
                Toggle("Menu bar", isOn: $model.menuBarItem)
                    .disabled(model.menuBarItem && !model.showInDock && !hasShortcut)
                Toggle("Dock", isOn: $model.showInDock)
                    .disabled(model.showInDock && !model.menuBarItem && !hasShortcut)
            } header: {
                Text("Show in")
            } footer: {
                if !model.menuBarItem, !model.showInDock {
                    Text("With both off, the keyboard shortcut still opens the window.")
                } else if !hasShortcut, model.menuBarItem != model.showInDock {
                    Text("Set a shortcut to switch this off as well.")
                }
            }
            Section("Accent") {
                Picker("Color", selection: Binding(
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
                .pickerStyle(.segmented)
                if case .custom(let color) = model.accent {
                    ColorPicker("Custom color", selection: Binding(
                        get: { Color(nsColor: color) },
                        set: { model.accent = .custom(NSColor($0)) }
                    ), supportsOpacity: false)
                }
            }
        }
        .formStyle(.grouped)
        .tint(model.accentColor)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        // Otherwise the always-on-top memo window covers it.
        .background(WindowReader { $0.level = .floating })
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

    // A custom color starts as a frozen copy of the system accent, resolved in the current appearance.
    private static func systemAccentSnapshot() -> NSColor? {
        var color: NSColor?
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            color = NSColor.controlAccentColor.usingColorSpace(.sRGB)
        }
        return color
    }
}
