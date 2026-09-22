import SwiftUI

@main
struct MemosApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    private var model: AppModel { delegate.model }

    // The memo window is the delegate's panel, not a scene; the commands hang off Settings.
    var body: some Scene {
        Settings {
            SettingsView()
                .environment(model)
                .environment(delegate.updater)
        }
        .commands { AppCommands(model: model, updater: delegate.updater) }

        MenuBarExtra(isInserted: Binding(get: { model.menuBarItem }, set: { model.menuBarItem = $0 })) {
            Button("Open \(Bundle.main.displayName)") { model.showWindow() }
            Button("New Memo") { Task { await model.newMemo() } }
            Divider()
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Quit \(Bundle.main.displayName)") { NSApp.terminate(nil) }
        } label: {
            MenuBarLabel(model: model)
        }
    }
}

extension Bundle {
    var displayName: String {
        object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ""
    }

    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var buildNumber: String {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }
}

/// The menu bar item's image. A view of its own, so the icon the model holds is read where a change to it
/// is seen; the image alone, since a label with text beside it draws that text in the menu bar as well.
private struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        model.menuBarIcon.image.accessibilityLabel(Bundle.main.displayName)
    }
}

/// What the menu bar item shows: the app's own mark, drawn as a template so the menu bar colors it, or
/// one of the system's symbols.
enum MenuBarIcon: String, CaseIterable, Identifiable {
    case squiggle, scribble, note, compose

    var id: String { rawValue }

    var title: String {
        switch self {
        case .squiggle: "Squiggle"
        case .scribble: "Scribble"
        case .note: "Note"
        case .compose: "Compose"
        }
    }

    /// The mark itself, held to the symbols' own size, which the app's asset would otherwise overrun.
    @ViewBuilder var image: some View {
        if let systemImage {
            Image(systemName: systemImage)
        } else {
            Image(Self.asset).resizable().scaledToFit().frame(height: 13)
        }
    }

    /// nil for the app's own mark, which is an asset rather than a symbol.
    var systemImage: String? {
        switch self {
        case .squiggle: nil
        case .scribble: "scribble"
        case .note: "note.text"
        case .compose: "square.and.pencil"
        }
    }

    static let asset = "MenuBarIcon"
}
