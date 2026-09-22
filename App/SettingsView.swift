import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Updater.self) private var updater
    @Environment(\.colorScheme) private var colorScheme
    @State private var globalShortcut = KeyboardShortcuts.getShortcut(for: .toggleWindow)
    /// The empty box a key is being typed into, below one of a shortcut's others.
    @State private var adding: ShortcutRow?
    @State private var hovered: ShortcutRow.ID?

    private var hasShortcut: Bool { globalShortcut != nil }

    var body: some View {
        TabView {
            Tab("App", systemImage: "macwindow") { app }
            Tab("Shortcuts", systemImage: "keyboard") { shortcuts }
            Tab("About", systemImage: "info.circle") { about }
        }
        .tint(model.accentColor)
        // Otherwise the always-on-top memo window covers it.
        .background(WindowReader { $0.level = .floating })
        // Opened from the panel while another app is in front, Settings would open behind it.
        .onAppear { NSApp.activate() }
    }

    private var app: some View {
        @Bindable var model = model
        return Form {
            Section {
                // The icons alone: their names would say less than the shapes, in the menu and in the bar.
                Picker("Menu bar icon", selection: $model.menuBarIcon) {
                    ForEach(MenuBarIcon.allCases) { icon in
                        Group {
                            if let symbol = icon.systemImage {
                                Image(systemName: symbol)
                            } else {
                                Image(MenuBarIcon.asset)
                            }
                        }
                        .accessibilityLabel(icon.title)
                        .tag(icon)
                    }
                }
                .tint(.primary)
                .disabled(!model.menuBarItem)
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
                        Text("Set a shortcut in Shortcuts to switch this off as well.")
                    }
                }
            }
            Section("Window") {
                Toggle("Always on top", isOn: $model.floating)
                Toggle("Side pane at launch", isOn: $model.sidePaneAtLaunch)
            }
            Section {
                Picker("Controls", selection: $model.standardControls) {
                    Text("Compact").tag(false)
                    Text("Standard").tag(true)
                }
                .tint(.primary)
                Picker("Text size", selection: $model.textSize) {
                    ForEach(TextSize.allCases) { size in
                        Text(size.title).tag(size.points)
                    }
                }
                .tint(.primary)
                LabeledContent("Opacity") {
                    Slider(value: $model.windowOpacity, in: 0...1) { Text("Opacity") }
                        .labelsHidden()
                }
                Picker("Tint", selection: Binding(
                    get: { model.windowTint != nil },
                    set: { tinted in
                        // A tint starts as the window's own color, so the well opens on what is on screen.
                        model.windowTint = tinted ? WindowBackdrop.baseColor(for: colorScheme) : nil
                    }
                )) {
                    Text("None").tag(false)
                    Text("Custom").tag(true)
                }
                .tint(.primary)
                if let tint = model.windowTint {
                    ColorPicker("Tint color", selection: Binding(
                        get: { Color(nsColor: tint) },
                        set: { if let picked = Self.stored($0) { model.windowTint = picked } }
                    ), supportsOpacity: false)
                }
                Picker("Accent", selection: Binding(
                    get: { AccentChoice(model.accent) },
                    set: { choice in
                        switch choice {
                        case .standard: model.accent = .standard
                        case .system: model.accent = .system
                        case .custom: if let color = Self.systemAccentSnapshot() { model.accent = .custom(color) }
                        }
                    }
                )) {
                    Text("Default").tag(AccentChoice.standard)
                    Text("System").tag(AccentChoice.system)
                    Text("Custom").tag(AccentChoice.custom)
                }
                .tint(.primary)
                if case .custom(let color) = model.accent {
                    ColorPicker("Accent color", selection: Binding(
                        get: { Color(nsColor: color) },
                        set: { if let picked = Self.stored($0) { model.accent = .custom(picked) } }
                    ), supportsOpacity: false)
                }
            } header: {
                Text("Appearance")
            } footer: {
                HStack {
                    Spacer()
                    Button("Reset Appearance") { model.resetAppearance() }
                        .buttonStyle(.bordered)
                        .tint(.primary)
                        .disabled(model.isDefaultAppearance)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var shortcuts: some View {
        let conflicts = model.shortcuts.conflicts
        return Form {
            Section("Global Shortcuts") {
                LabeledContent("Show or hide the window") {
                    KeyRecorder(label: globalShortcut?.description, conflict: nil, onRecord: recordGlobal) {
                        KeyboardShortcuts.setShortcut(nil, for: .toggleWindow)
                        globalShortcut = nil
                    }
                }
            }
            Section {
                ForEach(model.shortcuts.rows(for: Shortcut.app, adding: adding)) { row($0, conflicts: conflicts) }
            } header: {
                Text("Memos")
            } footer: {
                Text("Click a shortcut to change it. Hover a row to add another key.")
            }
            Section {
                ForEach(model.shortcuts.rows(for: Shortcut.editor, adding: adding)) { row($0, conflicts: conflicts) }
            } header: {
                Text("Editor")
            } footer: {
                HStack {
                    Spacer()
                    Button("Restore Defaults") {
                        model.shortcuts.reset()
                        KeyboardShortcuts.reset(.toggleWindow)
                        globalShortcut = KeyboardShortcuts.getShortcut(for: .toggleWindow)
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                    .disabled(model.shortcuts.isDefault && globalShortcut == KeyboardShortcuts.Name.toggleWindow.initialShortcut)
                }
            }
        }
        .formStyle(.grouped)
        // The list outgrows a laptop screen, so this tab scrolls at a set height.
        .frame(width: 420, height: 560)
    }

    private var about: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Bundle.main.displayName).font(.title2.weight(.semibold))
                        Text("Version \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                LabeledContent("Updates") {
                    Button("Check for Updates…") { updater.check() }
                        .buttonStyle(.bordered)
                        .tint(.primary)
                        .disabled(!updater.canCheck)
                }
            } footer: {
                Text(updater.isAvailable ? "The app checks on its own and offers what it finds." : "A build from the tree carries no updater.")
            }
            Section {
                Link("Source and releases", destination: URL(string: "https://github.com/aicayzer/memos")!)
                Link("License", destination: URL(string: "https://github.com/aicayzer/memos/blob/main/LICENSE")!)
            }
            // A link is drawn in the system's link color, which is blue whatever the app's accent is.
            .foregroundStyle(.tint)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A global hotkey takes its key before any window sees it, so it cannot be one the system or the app's
    /// own menu already uses; and pressed with no text field in mind, Option alone will do as a modifier.
    private func recordGlobal(_ event: NSEvent) -> Bool {
        guard let shortcut = KeyboardShortcuts.Shortcut(event: event), let combo = KeyCombo(event: event), combo.isHotkey,
              !shortcut.isTakenBySystem, NSApp.mainMenu.flatMap(combo.menuItem(in:)) == nil else { return false }
        KeyboardShortcuts.setShortcut(shortcut, for: .toggleWindow)
        globalShortcut = shortcut
        return true
    }

    private func row(_ row: ShortcutRow, conflicts: [KeyCombo: [Shortcut]]) -> some View {
        LabeledContent(row.isFirst ? row.shortcut.title : "") {
            HStack(spacing: 6) {
                if row.key != nil {
                    Button { adding = ShortcutRow(shortcut: row.shortcut, index: row.index + 1, key: nil, isAdded: true) } label: {
                        Image(systemName: "plus.circle").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .opacity(hovered == row.id ? 1 : 0)
                    .accessibilityLabel("Add Shortcut")
                }
                KeyRecorder(
                    label: row.key?.label,
                    conflict: row.key.flatMap { Self.others(sharing: $0, with: row.shortcut, in: conflicts) },
                    recordsOnAppear: row.isAdded
                ) { event in
                    // The global hotkey takes its chord before the menu could, so no shortcut may share it.
                    guard let recorded = KeyCombo(event: event), recorded.isShortcut,
                          globalShortcut == nil || KeyboardShortcuts.Shortcut(event: event) != globalShortcut else { return false }
                    adding = nil
                    model.shortcuts.record(recorded, in: row)
                    return true
                } onClear: {
                    adding = nil
                    model.shortcuts.clear(row)
                } onCancel: {
                    adding = nil
                }
            }
        }
        .onHover { inside in
            if inside {
                hovered = row.id
            } else if hovered == row.id {
                hovered = nil
            }
        }
        .contextMenu {
            if row.key != nil {
                Button("Add Shortcut") { adding = ShortcutRow(shortcut: row.shortcut, index: row.index + 1, key: nil, isAdded: true) }
                Button("Remove Shortcut") { model.shortcuts.clear(row) }
            }
            Button("Reset to Default") { model.shortcuts.reset(row.shortcut) }
                .disabled(model.shortcuts.isDefault(row.shortcut))
        }
    }

    private static func others(sharing key: KeyCombo, with shortcut: Shortcut, in conflicts: [KeyCombo: [Shortcut]]) -> String? {
        let others = (conflicts[key] ?? []).filter { $0 != shortcut }.map(\.title)
        return others.isEmpty ? nil : "Also " + others.joined(separator: ", ")
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
            color = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? Accent.standardColor.usingColorSpace(.sRGB)
        }
        return color
    }
}
