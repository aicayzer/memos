import AppKit
import SwiftUI
import Testing
@testable import Memos

@MainActor
@Suite(.serialized, .opensWindows)
struct EditorPolishTests {
    @Test func nativeViewportCountsAndResizableSidebar() async throws {
        let now = Date.now
        let titles = ["A quieter place to collect unfinished thoughts", "Things worth trying", "Notes for Friday", "Ideas for the next Memos update", "The books I keep coming back to", "Kitchen measurements and the shelf by the window", "Walking route from the station to the lake"]
        let memos = titles.enumerated().map { index, title in
            Memo(id: UUID(), markdown: "# \(title)\n\nHello **café** 👨‍👩‍👧‍👦\n\n" + (1...60).map { "Paragraph \($0): a little room to keep writing." }.joined(separator: "\n\n"), favorite: index < 2, createdAt: now, updatedAt: now.addingTimeInterval(-Double(index * 12_000)))
        }
        let suite = "editor-polish-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "sidePaneAtLaunch")
        defaults.set(true, forKey: "paneRoom")
        defaults.set(1.0, forKey: "windowOpacity")
        let editor = EditorController(images: FakeImageStore())
        let model = AppModel(store: ChangeableStore(memos), images: FakeImageStore(), defaults: defaults, editor: editor)
        let window = MemoPanel(content: MainView().environment(model), restoresFrame: false)
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
            defaults.removePersistentDomain(forName: suite)
        }
        window.setContentSize(NSSize(width: 820, height: 640))
        model.attach(window)
        window.makeKeyAndOrderFront(nil)
        await model.start()
        await model.open(memos[0].id)
        _ = try await editor.snapshot()
        for _ in 0..<100 {
            if editor.counts != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let initialCounts = try #require(editor.counts)
        #expect(initialCounts.words > 100)
        let counts = editor.counts
        editor.receive(.textCounts(EditorCounts(characters: 0, words: 0), documentID: "different", generation: 2))
        #expect(editor.counts == counts)
        let insets = try #require(try await editor.webView.evaluateJavaScript("window.editor.viewport().insets") as? [String: Int])
        #expect(insets["top"] == 24)
        #expect(insets["bottom"] == 96)
        let contentView = try #require(window.contentView)
        var split = try #require(findSplit(in: contentView))
        #expect(abs(split.subviews[0].frame.width - 220) <= 1)
        split.setPosition(300, ofDividerAt: 0)
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        #expect(abs(model.sidePaneWidth - 300) <= 1)
        #expect(defaults.double(forKey: "sidePaneWidth") > 290)
        model.toggleSidePane()
        try await Task.sleep(for: .milliseconds(100))
        model.toggleSidePane()
        try await Task.sleep(for: .milliseconds(100))
        split = try #require(findSplit(in: contentView))
        #expect(abs(split.subviews[0].frame.width - 300) <= 1)
        if ProcessInfo.processInfo.environment["MEMOS_CAPTURE_PREVIEW"] == "1" {
            let directory = FileManager.default.temporaryDirectory.appending(path: "EditorPolishPreview")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            print("Native Memos previews: \(directory.path)")
            try await capture(window, editor: editor, to: directory.appending(path: "memos-sidebar-wide.png"))
            split.setPosition(220, ofDividerAt: 0)
            window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            try await capture(window, editor: editor, to: directory.appending(path: "memos-sidebar-220.png"))
        }
    }

    @Test func countsFollowTypingWhenConditionalRefreshKeepsTheOldScope() async throws {
        let editor = EditorController(images: FakeImageStore())
        editor.documentID = "original"
        editor.load("Original\n")
        _ = try await editor.snapshot()
        for _ in 0..<100 {
            if editor.counts?.characters == 8 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        _ = try await editor.webView.evaluateJavaScript("""
        window.originalRefresh = window.editor.refresh;
        window.editor.refresh = (...args) => {
          window.editor.pasteAsPlainText(' typed');
          return window.originalRefresh(...args);
        }; true
        """)
        guard case .edited(let text) = try await editor.refresh("External\n", documentID: "next", expecting: "Original\n") else {
            Issue.record("Typing must keep the original scope"); return
        }
        #expect(text.contains("Original typed"))
        for _ in 0..<100 {
            if editor.counts?.characters == 14 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(editor.documentID == "original")
        #expect(editor.counts == EditorCounts(characters: 14, words: 2))
    }

    private func findSplit(in view: NSView) -> NSSplitView? {
        if let split = view as? NSSplitView { return split }
        return view.subviews.lazy.compactMap { findSplit(in: $0) }.first
    }

    private func capture(_ window: NSWindow, editor: EditorController, to url: URL) async throws {
        let view = try #require(window.contentView)
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(bitmap)
        let nativePNG = try #require(bitmap.representation(using: .png, properties: [:]))
        let original = try #require(NSImage(data: nativePNG))
        let webImage = try await editor.webView.takeSnapshot(configuration: nil)
        image.lockFocus()
        let rect = editor.webView.convert(editor.webView.bounds, to: view)
        let target = NSRect(x: rect.minX, y: view.bounds.height - rect.maxY, width: rect.width, height: rect.height)
        webImage.draw(in: target)
        // WebKit composites separately from the hosting view. Keep native chrome
        // above its snapshot in the reserved bottom band.
        let band = NSRect(x: target.minX, y: target.minY, width: target.width, height: 96)
        original.draw(in: band, from: band, operation: .sourceOver, fraction: 1)
        image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)
        let rendered = try #require(NSBitmapImageRep(data: tiff))
        try #require(rendered.representation(using: .png, properties: [:])).write(to: url)
    }
}
