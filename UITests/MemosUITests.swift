import AppKit
import Darwin
import XCTest

@MainActor
final class MemosUITests: XCTestCase {
    func testEditingSearchSettingsAndDockPreserveMemo() throws {
        let fixture = try launchMemos()
        let app = fixture.app
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
        let process = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: fixture.bundleIdentifier).first)
        expectPolicy(.regular, process: process)
        dock.click()
        expectPolicy(.accessory, process: process)
        selectTab("Appearance", in: settings)
        XCTAssertTrue(settings.staticTexts["Opacity"].exists)
        attach(app, name: "Memos Appearance settings without Dock icon")
        selectTab("Storage", in: settings)
        XCTAssertTrue(settings.staticTexts["Keep memos"].exists)
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

    func testBlankParagraphsSurviveMemoSwitchAndRelaunch() throws {
        let fixture = try launchMemos()
        let app = fixture.app
        let editor = app.webViews.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 15), app.debugDescription)
        app.typeText("Spacing example")
        app.typeKey(.return, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        app.typeText("First section")
        app.typeKey(.return, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        app.typeText("Last paragraph")
        expectText("Last paragraph", in: editor)
        let before = try XCTUnwrap(editor.value as? String)
        attach(app, name: "Authored paragraph spacing")
        app.typeKey("n", modifierFlags: .command)
        app.typeText("Other disposable memo")
        expectText("Other disposable memo", in: editor)
        app.typeKey("p", modifierFlags: .command)
        let search = app.textFields["Search memos…"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        app.typeText("Spacing example")
        app.typeKey(.return, modifierFlags: [])
        expectValue(before, in: editor)
        attach(app, name: "Paragraph spacing after switching back")
        let data = try Data(contentsOf: fixture.folder.appending(path: "store.json"))
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let memos = try XCTUnwrap(saved["memos"] as? [[String: Any]])
        XCTAssertTrue(memos.contains { ($0["markdown"] as? String)?.contains("<br />") == true },
                      "The saved memo must retain authored spacer paragraphs.")
        app.terminate()
        app.launch()
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        expectValue(before, in: editor)
        attach(app, name: "Paragraph spacing after relaunch")
    }

    func testDevelopmentGlobalShortcutsDoNotActivatePad() throws {
        let fixture = try launchMemos()
        let app = fixture.app
        let editor = app.webViews.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 15), app.debugDescription)
        app.typeText("Disposable global shortcut memo")
        expectText("Disposable global shortcut memo", in: editor)
        let padID = "me.cyzr.pad.dev"
        let padWasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: padID).isEmpty
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        XCTAssertTrue(finder.wait(for: .runningForeground, timeout: 5))
        let menu = finder.menuBars.firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.typeKey("b", modifierFlags: [.control, .option, .command])
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: editor)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed)
        expectText("Disposable global shortcut memo", in: editor)
        XCTAssertNotEqual(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, padID)
        if !padWasRunning { XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: padID).isEmpty) }
        menu.typeKey("b", modifierFlags: [.control, .option, .command])
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false OR hittable == false"), object: editor)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
        menu.typeKey("m", modifierFlags: [.control, .option, .command])
        let empty = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value MATCHES %@", "\\s*"), object: editor)
        XCTAssertEqual(XCTWaiter.wait(for: [empty], timeout: 5), .completed, editor.debugDescription)
        XCTAssertNotEqual(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, padID)
        if !padWasRunning { XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: padID).isEmpty) }
        attach(app, name: "Memos development global shortcuts")
    }

    func testTableAndLiteralPasteSurviveSwitchAndRelaunch() throws {
        let fixture = try launchMemos()
        let app = fixture.app
        let editor = app.webViews.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        let previousClipboard = captureClipboard()
        defer { restoreClipboard(previousClipboard) }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("Name\tValue\nAlice\t42", forType: .string)
        pasteboard.setString("<table><tr><th>Name</th><th>Value</th></tr><tr><td>Alice</td><td>42</td></tr></table>", forType: .html)
        app.typeKey("v", modifierFlags: .command)
        expectText("Alice", in: editor)
        app.typeKey("c", modifierFlags: [.command, .shift])
        expectClipboard { $0.contains("| Alice") && $0.contains("42") }
        app.typeKey("n", modifierFlags: .command)
        pasteboard.clearContents()
        pasteboard.setString("Literal fixture\n**literal**\nLast line", forType: .string)
        app.typeKey("v", modifierFlags: [.command, .option, .shift])
        expectText("**literal**", in: editor)
        expectText("Last line", in: editor)
        app.typeKey("c", modifierFlags: [.command, .shift])
        expectClipboard { $0.contains("\\*\\*literal\\*\\*") && $0.contains("Last line") }
        let before = try XCTUnwrap(editor.value as? String)
        app.typeKey("n", modifierFlags: .command)
        app.typeText("Another fixture")
        app.typeKey("p", modifierFlags: .command)
        let search = app.textFields["Search memos…"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        app.typeText("Literal fixture")
        app.typeKey(.return, modifierFlags: [])
        expectValue(before, in: editor)
        app.terminate()
        app.launch()
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        expectValue(before, in: editor)
    }

    func testMixedImagePasteRetainsHeadingAndExportsPortableAttachments() throws {
        let fixture = try launchMemos()
        let app = fixture.app
        let editor = app.webViews.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        let previousClipboard = captureClipboard()
        defer { restoreClipboard(previousClipboard) }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.setColor(.blue, atX: 0, y: 0)
        let image = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("Before Photo After", forType: .string)
        pasteboard.setString("<h2>Before</h2><p><img src='data:image/png;base64,\(image.base64EncodedString())' alt='Photo'></p><p>After</p>", forType: .html)
        let input = NSMutableAttributedString(string: "Before\n\u{FFFC}\nAfter")
        let wrapper = FileWrapper(regularFileWithContents: image)
        wrapper.preferredFilename = "fixture.png"
        let attachment = NSTextAttachment(fileWrapper: wrapper)
        input.replaceCharacters(in: NSRange(location: 7, length: 1), with: NSAttributedString(attachment: attachment))
        pasteboard.setData(try input.data(from: NSRange(location: 0, length: input.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]), forType: .rtfd)
        app.typeKey("v", modifierFlags: .command)
        expectText("After", in: editor)
        app.typeKey("c", modifierFlags: [.command, .shift])
        expectClipboard { $0.contains("## Before") && $0.contains("![Photo](images/") && $0.contains("After") }
        app.typeKey("a", modifierFlags: .command)
        app.typeKey("c", modifierFlags: .command)
        let exported = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in pasteboard.data(forType: .rtfd) != nil }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [exported], timeout: 10), .completed)
        let html = try XCTUnwrap(pasteboard.string(forType: .html))
        XCTAssertTrue(html.contains("data:image/png;base64,"))
        XCTAssertFalse(html.contains("memo-image:"))
        let rich = try NSAttributedString(data: XCTUnwrap(pasteboard.data(forType: .rtfd)), options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)
        XCTAssertTrue(rich.string.contains("Before"))
        XCTAssertTrue(rich.string.contains("After"))
        var attachments = 0
        rich.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rich.length)) { value, _, _ in
            if value is NSTextAttachment { attachments += 1 }
        }
        XCTAssertEqual(attachments, 1)
    }

    func testNewMemoAcceptsImmediateTyping() throws {
        let fixture = try launchMemos()
        let app = fixture.app
        let editor = app.webViews.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        app.typeText("Spacing example")
        app.typeKey(.return, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        app.typeText("First section")
        app.typeKey(.return, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        app.typeText("Last paragraph")
        expectText("Last paragraph", in: editor)
        for index in 0..<5 {
            app.typeKey("n", modifierFlags: .command)
            let text = "Other disposable memo \(index) \(UUID().uuidString)"
            app.typeText(text)
            expectText(text, in: editor)
        }
    }

    private func expectClipboard(_ matches: @escaping (String) -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            matches(NSPasteboard.general.string(forType: .string) ?? "")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
    }

    private func captureClipboard() -> [NSPasteboardItem] {
        (NSPasteboard.general.pasteboardItems ?? []).map { original in
            let item = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) { item.setData(data, forType: type) }
            }
            return item
        }
    }

    private func restoreClipboard(_ items: [NSPasteboardItem]) {
        NSPasteboard.general.clearContents()
        if !items.isEmpty { NSPasteboard.general.writeObjects(items) }
    }

    private struct Fixture {
        let app: XCUIApplication
        let folder: URL
        let bundleIdentifier: String
    }

    private func launchMemos() throws -> Fixture {
        continueAfterFailure = false
        let testBundleID = try XCTUnwrap(Bundle(for: Self.self).bundleIdentifier)
        guard testBundleID.hasSuffix(".uitests") else {
            throw NSError(domain: "MemosUITests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Unexpected UI test bundle identifier: \(testBundleID)"])
        }
        let bundleIdentifier = String(testBundleID.dropLast(".uitests".count))
        let app = XCUIApplication()
        XCTAssertEqual(app.state, .notRunning, "Leave an existing development app untouched.")
        let account = try XCTUnwrap(getpwuid(getuid()))
        let home = URL(fileURLWithPath: String(cString: account.pointee.pw_dir), isDirectory: true)
        let folder = home
            .appending(path: "Library/Containers/\(bundleIdentifier)/Data/tmp/memos-ui-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = folder.appending(path: "store.json")
        app.launchEnvironment["MEMOS_STORE"] = store.path
        app.launchArguments = ["-showInDock", "YES", "-menuBarItem", "NO", "-floating", "NO",
                               "-sidePaneAtLaunch", "NO", "-shortcuts", "invalid",
                               "-KeyboardShortcuts_toggleWindow", #""{\"carbonKeyCode\":11,\"carbonModifiers\":6400}""#,
                               "-KeyboardShortcuts_newMemo", #""{\"carbonKeyCode\":46,\"carbonModifiers\":6400}""#]
        let fixture = Fixture(app: app, folder: folder, bundleIdentifier: bundleIdentifier)
        addTeardownBlock { @MainActor in self.finish(fixture) }
        app.launch()
        return fixture
    }

    private func finish(_ fixture: Fixture) {
        attach(fixture.app, name: "Final Memos accessibility state")
        fixture.app.terminate()
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
