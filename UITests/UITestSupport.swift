import AppKit
import XCTest

/// UI tests drive the real screen, keyboard and clipboard, so they run only where the caller says the session is
/// isolated. Pass it as `TEST_RUNNER_MEMOS_UI_TESTS=1`, as CI does.
enum IsolatedSession {
    static let variable = "MEMOS_UI_TESTS"
    static let developmentIdentifier = "me.cyzr.memos.dev"

    static func require() throws {
        guard ProcessInfo.processInfo.environment[variable] == "1" else {
            throw NSError(domain: "MemosUITests", code: 2, userInfo: [NSLocalizedDescriptionKey:
                "UI tests take over the screen, keyboard and clipboard. Run them only in an isolated session, with TEST_RUNNER_\(variable)=1 in the environment of xcodebuild."])
        }
    }
}

/// A global shortcut pressed while another app is in front, as a user would.
enum GlobalShortcut {
    private static let finder = "com.apple.finder"

    /// Brings Finder to the front with AppKit, then sends the key to it. Resolving Finder's menu bar first, as the
    /// test once did, makes XCTest take and wait on a snapshot of Finder before the key. A `CGEvent` would skip
    /// XCTest altogether, but posting one needs an Accessibility grant that the test runner lacks.
    @MainActor
    static func pressFromFinder(_ key: String, modifiers: XCUIElement.KeyModifierFlags) throws {
        let app = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: finder).first)
        app.activate()
        let deadline = Date().addingTimeInterval(5)
        while NSWorkspace.shared.frontmostApplication?.bundleIdentifier != finder, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, finder, "Finder did not become frontmost.")
        XCUIApplication(bundleIdentifier: finder).typeKey(key, modifierFlags: modifiers)
    }
}
