import Foundation
import Sparkle

/// Sparkle behind one object: the menu asks it to check and reads whether it can. A Debug build carries no
/// updater, so a build from the tree is never replaced by a release.
@MainActor
@Observable
final class Updater {
    private let controller: SPUStandardUpdaterController?
    private(set) var canCheck = false
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init() {
        #if DEBUG
        controller = nil
        #else
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheck = updater.canCheckForUpdates }
        }
        #endif
    }

    var isAvailable: Bool { controller != nil }

    func check() {
        controller?.checkForUpdates(nil)
    }
}
