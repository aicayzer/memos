import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var login = LoginItemSettings()
    @State private var globalShortcut = KeyboardShortcuts.getShortcut(for: .toggleWindow)
    @State private var newMemoShortcut = KeyboardShortcuts.getShortcut(for: .newMemo)
    /// The empty box a key is being typed into, below one of a shortcut's others.
    @State private var adding: ShortcutRow?
    @State private var hovered: ShortcutRow.ID?

    private var hasShortcut: Bool { globalShortcut != nil }

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { general }
            Tab("Appearance", systemImage: "paintbrush") { appearance }
            Tab("Storage", systemImage: "externaldrive") { storage }
            Tab("Shortcuts", systemImage: "keyboard") { shortcuts }
        }
        .frame(width: 460, height: 560)
        .tint(model.accentColor)
        // Otherwise the always-on-top memo window covers it.
        .background(WindowReader {
            #if DEBUG
            $0.level = .normal
            #else
            $0.level = .floating
            #endif
        })
        // Opened from the panel while another app is in front, Settings would open behind it.
        .onAppear { NSApp.activate(); login.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in login.refresh() }
    }

    private var general: some View {
        @Bindable var model = model
        return Form {
            Section {
                Toggle("Open at login", isOn: Binding(get: { login.enabled }, set: { enabled in
                    Task { await login.setEnabled(enabled) }
                }))
                .disabled(login.updating)
                if login.status == .requiresApproval {
                    Button("Allow in Login Items…") { login.openSystemSettings() }
                }
                if let error = login.error { Text(error).foregroundStyle(.red) }
                // Without a shortcut, the last way back to the window cannot be switched off.
                Toggle("Show in Dock", isOn: $model.showInDock)
                    .accessibilityIdentifier("showInDock")
                    .disabled(model.showInDock && !model.menuBarItem && !hasShortcut)
                Toggle("Show in menu bar", isOn: $model.menuBarItem)
                    .disabled(model.menuBarItem && !model.showInDock && !hasShortcut)
                // A menu of icons rather than a picker: what is chosen is already shown as the menu's own
                // label, so a picker's check mark beside it would say it twice.
                LabeledContent("Menu bar icon") {
                    Menu {
                        ForEach(MenuBarIcon.allCases) { icon in
                            Button { model.menuBarIcon = icon } label: {
                                icon.image.accessibilityLabel(icon.title)
                            }
                        }
                    } label: {
                        model.menuBarIcon.image
                    }
                    .menuStyle(.button)
                    .menuIndicator(.visible)
                    .buttonStyle(.borderless)
                    .tint(.primary)
                    .fixedSize()
                    .accessibilityLabel("Menu bar icon")
                    .accessibilityValue(model.menuBarIcon.title)
                }
                .disabled(!model.menuBarItem)
            } header: {
                Text("App")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let error = model.spotlightError { Text(error).foregroundStyle(.red) }
                    if let error = model.activationPolicyError { Text(error).foregroundStyle(.red) }
                    if !model.menuBarItem, !model.showInDock, let globalShortcut {
                        Text("Open Memos with \(globalShortcut.description).")
                    } else if !hasShortcut, model.menuBarItem != model.showInDock {
                        Text("Set a shortcut in Shortcuts to switch this off as well.")
                    }
                }
            }
            Section("Appearance") {
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
            }
            Section("About") {
                LabeledContent("Version", value: "\(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                Link(destination: URL(string: "https://github.com/aicayzer/memos")!) {
                    Text("Source Code").foregroundStyle(model.accentColor)
                }
                Link(destination: URL(string: "https://github.com/aicayzer/memos/releases")!) {
                    Text("Releases").foregroundStyle(model.accentColor)
                }
                Link(destination: URL(string: "https://github.com/aicayzer/memos/blob/main/LICENSE")!) {
                    Text("License").foregroundStyle(model.accentColor)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var appearance: some View {
        @Bindable var model = model
        return Form {
            Section("Window") {
                Toggle("Always on top", isOn: $model.floating)
                Toggle("Show sidebar at launch", isOn: $model.sidePaneAtLaunch)
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
                    HStack(spacing: 8) {
                        Slider(value: $model.windowOpacity, in: 0...1) { Text("Opacity") }
                            .labelsHidden()
                            .frame(width: 115)
                        Text(model.windowOpacity, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .frame(width: 38, alignment: .trailing)
                    }
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
            } header: {
                Text("Editor")
            } footer: {
                HStack {
                    Spacer()
                    Button("Reset Appearance") {
                        model.textSize = AppModel.defaultTextSize
                        model.standardControls = false
                        model.windowOpacity = AppModel.defaultWindowOpacity
                        model.windowTint = nil
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                    .disabled(model.textSize == AppModel.defaultTextSize && !model.standardControls
                              && model.windowOpacity == AppModel.defaultWindowOpacity && model.windowTint == nil)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var storage: some View {
        Form { StorageSettingsView() }
            .formStyle(.grouped)
    }

    private var shortcuts: some View {
        let conflicts = model.shortcuts.conflicts
        return Form {
            Section("Global Shortcuts") {
                globalRow("Show or hide Memos", .toggleWindow, $globalShortcut)
                globalRow("New memo", .newMemo, $newMemoShortcut)
            }
            Section {
                ForEach(model.shortcuts.rows(for: Shortcut.app, adding: adding)) { row($0, conflicts: conflicts) }
            } header: {
                Text("Memos")
            } footer: {
                Text("Click to change, the cross to remove, hover a row to add a key.")
            }
            Section {
                ForEach(model.shortcuts.rows(for: Shortcut.editor, adding: adding)) { row($0, conflicts: conflicts) }
            } header: {
                Text("Formatting")
            } footer: {
                HStack {
                    Spacer()
                    Button("Restore Defaults") {
                        adding = nil
                        model.shortcuts.reset()
                        KeyboardShortcuts.reset(.toggleWindow, .newMemo)
                        globalShortcut = KeyboardShortcuts.getShortcut(for: .toggleWindow)
                        newMemoShortcut = KeyboardShortcuts.getShortcut(for: .newMemo)
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                    .disabled(model.shortcuts.isDefault && Self.globalNames.allSatisfy { KeyboardShortcuts.getShortcut(for: $0) == $0.initialShortcut })
                }
            }
        }
        .formStyle(.grouped)
    }

    private static let globalNames: [KeyboardShortcuts.Name] = [.toggleWindow, .newMemo]

    private func globalRow(
        _ title: String, _ name: KeyboardShortcuts.Name, _ shortcut: Binding<KeyboardShortcuts.Shortcut?>
    ) -> some View {
        LabeledContent(title) {
            KeyRecorder(
                label: shortcut.wrappedValue?.description,
                conflict: nil,
                onRecord: { recordGlobal($0, for: name, into: shortcut) },
                onClear: {
                    KeyboardShortcuts.setShortcut(nil, for: name)
                    shortcut.wrappedValue = nil
                    if !hasShortcut && !model.showInDock && !model.menuBarItem { model.menuBarItem = true }
                }
            )
        }
    }

    /// A global hotkey takes its key before any window sees it, so it cannot be one the system, the app's
    /// own menu or the other hotkey already uses; and pressed with no text field in mind, Option alone will
    /// do as a modifier.
    private func recordGlobal(
        _ event: NSEvent, for name: KeyboardShortcuts.Name, into shortcut: Binding<KeyboardShortcuts.Shortcut?>
    ) -> Bool {
        guard let recorded = KeyboardShortcuts.Shortcut(event: event), let combo = KeyCombo(event: event), combo.isHotkey,
              !recorded.isTakenBySystem, NSApp.mainMenu.flatMap(combo.menuItem(in:)) == nil,
              !Self.globalNames.contains(where: { $0 != name && KeyboardShortcuts.getShortcut(for: $0) == recorded }),
              !Shortcut.allCases.contains(where: { model.shortcuts.keys(for: $0).contains(combo) })
        else { return false }
        KeyboardShortcuts.setShortcut(recorded, for: name)
        shortcut.wrappedValue = recorded
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
                          !Self.globalNames.contains(where: { KeyboardShortcuts.getShortcut(for: $0) == KeyboardShortcuts.Shortcut(event: event) }) else { return false }
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
                Button("Remove Shortcut") {
                    adding = nil
                    model.shortcuts.clear(row)
                }
            }
            Button("Reset to Default") {
                adding = nil
                model.shortcuts.reset(row.shortcut)
            }
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
