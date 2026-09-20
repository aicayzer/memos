import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Shortcut") {
                KeyboardShortcuts.Recorder("Show or hide the window", name: .toggleWindow)
            }
            Section("Window") {
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
            Section("Accent") {
                Picker("Color", selection: Binding(
                    get: { model.accent == nil },
                    set: { followsSystem in model.accent = followsSystem ? nil : NSColor.controlAccentColor }
                )) {
                    Text("System").tag(true)
                    Text("Custom").tag(false)
                }
                .pickerStyle(.segmented)
                if let accent = model.accent {
                    ColorPicker("Custom color", selection: Binding(
                        get: { Color(nsColor: accent) },
                        set: { model.accent = NSColor($0) }
                    ), supportsOpacity: false)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        // Otherwise the always-on-top memo window covers it.
        .background(WindowReader { $0.level = .floating })
    }
}
