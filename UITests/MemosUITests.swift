import AppKit
import XCTest

@MainActor
final class MemosUITests: XCTestCase {
    func testEditingSearchSettingsAndDockPreserveMemo() throws {
        let fixture = try launchMemos()
        let app = fixture.app
        defer { finish(fixture) }
        let editor = app.webViews.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 15), app.debugDescription)
        let first = "Disposable first memo \(UUID().uuidString)"
        app.typeText(first)
        expectText(first, in: editor)
        app.typeKey("n", modifierFlags: .command)
        let second = "Disposable second memo"
        app.typeText(second)
        expectText(second, in: editor)
        XCTAssertFalse((editor.value as? String ?? "").contains(first))

        app.typeKey("p", modifierFlags: .command)
        let search = app.textFields["Search memos…"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), app.debugDescription)
        // The overlay must take the first keystroke without an extra click.
        app.typeText(first)
        expectValue(first, in: search)
        app.typeKey(.return, modifierFlags: [])
        expectText(first, in: editor)
        app.typeKey(.downArrow, modifierFlags: .command)
        app.typeText(" Continued after search.")
        expectText("Continued after search.", in: editor)
        attach(app, name: "Memo edited after search")

        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), app.debugDescription)
        selectTab("General", in: settings)
        XCTAssertTrue(settings.staticTexts["Version"].exists)
        XCTAssertFalse(settings.buttons["Check for Updates…"].exists)
        XCTAssertFalse(settings.toolbars.buttons["TextPad"].exists)
        attach(app, name: "Memos General settings")
        let dock = settings.switches["showInDock"]
        XCTAssertTrue(dock.waitForExistence(timeout: 5), settings.debugDescription)
        let process = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).first)
        XCTAssertEqual(process.activationPolicy, .regular)
        dock.click()
        expectPolicy(.accessory, process: process)
        selectTab("Appearance", in: settings)
        XCTAssertTrue(settings.staticTexts["Opacity"].exists)
        attach(app, name: "Memos Appearance settings without Dock icon")
        selectTab("Storage", in: settings)
        XCTAssertTrue(settings.staticTexts["Store memos as Markdown files"].exists)
        attach(app, name: "Memos Storage settings")
        selectTab("Shortcuts", in: settings)
        XCTAssertFalse(settings.staticTexts["Show or hide TextPad"].exists)
        attach(app, name: "Memos Shortcuts settings")
        selectTab("General", in: settings)
        dock.click()
        expectPolicy(.regular, process: process)
        settings.buttons["_XCUI:CloseWindow"].click()
        editor.click()
        expectText(first, in: editor)
        expectText("Continued after search.", in: editor)
        app.typeKey(.downArrow, modifierFlags: .command)
        app.typeText(" Continued after Settings.")
        expectText("Continued after Settings.", in: editor)
        app.typeKey("s", modifierFlags: .command)
        attach(app, name: "Memo preserved after Settings and Dock changes")
    }

    func testDevelopmentGlobalShortcutsDoNotActivatePad() throws {
        let fixture = try launchMemos()
        let app = fixture.app
        defer { finish(fixture) }
        let editor = app.webViews.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 15), app.debugDescription)
        app.typeText("Disposable global shortcut memo")
        expectText("Disposable global shortcut memo", in: editor)
        let pad = XCUIApplication(bundleIdentifier: "me.cyzr.pad.dev")
        let padWasRunning = pad.state != .notRunning
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        XCTAssertTrue(finder.wait(for: .runningForeground, timeout: 5))
        let menu = finder.menuBars.firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.typeKey("b", modifierFlags: [.control, .option, .command])
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: editor)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed)
        expectText("Disposable global shortcut memo", in: editor)
        XCTAssertNotEqual(pad.state, .runningForeground)
        if !padWasRunning { XCTAssertEqual(pad.state, .notRunning) }
        menu.typeKey("b", modifierFlags: [.control, .option, .command])
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false OR hittable == false"), object: editor)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
        menu.typeKey("m", modifierFlags: [.control, .option, .command])
        expectValue("", in: editor)
        XCTAssertNotEqual(pad.state, .runningForeground)
        if !padWasRunning { XCTAssertEqual(pad.state, .notRunning) }
        attach(app, name: "Memos development global shortcuts")
    }

    private struct Fixture {
        let app: XCUIApplication
        let folder: URL
    }

    private func launchMemos() throws -> Fixture {
        continueAfterFailure = false
        let app = XCUIApplication()
        XCTAssertEqual(app.state, .notRunning, "Leave an existing development app untouched.")
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Containers/\(app.bundleIdentifier)/Data/tmp/memos-ui-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = folder.appending(path: "store.json")
        try Data("[]".utf8).write(to: store)
        app.launchEnvironment["MEMOS_STORE"] = store.path
        app.launchArguments = ["-showInDock", "YES", "-menuBarItem", "NO", "-floating", "NO",
                               "-sidePaneAtLaunch", "NO", "-shortcuts", "invalid",
                               "-KeyboardShortcuts_toggleWindow", #""{\"carbonKeyCode\":11,\"carbonModifiers\":6400}""#,
                               "-KeyboardShortcuts_newMemo", #""{\"carbonKeyCode\":46,\"carbonModifiers\":6400}""#]
        app.launch()
        return Fixture(app: app, folder: folder)
    }

    private func finish(_ fixture: Fixture) {
        attach(fixture.app, name: "Final Memos accessibility state")
        fixture.app.terminate()
        try? FileManager.default.removeItem(at: fixture.folder)
    }

    private func selectTab(_ title: String, in settings: XCUIElement) {
        let tab = settings.toolbars.buttons[title]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), settings.debugDescription)
        tab.click()
    }

    private func expectText(_ text: String, in editor: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", text), object: editor)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, editor.debugDescription)
    }

    private func expectValue(_ value: String, in element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, element.debugDescription)
    }

    private func expectPolicy(_ policy: NSApplication.ActivationPolicy, process: NSRunningApplication) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "activationPolicy == %d", policy.rawValue), object: process)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
