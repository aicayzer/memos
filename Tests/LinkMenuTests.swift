import AppKit
import Testing
@testable import Memos

@MainActor
@Suite struct LinkMenuTests {
    @Test func theMessageCarriesTheAddressWhetherItOpensAndThePoint() throws {
        let message = try #require(EditorMessage(body: ["type": "linkMenu", "href": "https://example.com", "openable": true, "x": 3, "y": 9.5]))
        guard case .linkMenu(let href, let openable, let point) = message else { Issue.record("not a link menu"); return }
        #expect(href == "https://example.com")
        #expect(openable)
        #expect(point == CGPoint(x: 3, y: 9.5))
        #expect(EditorMessage(body: ["type": "linkMenu", "openable": true, "x": 1, "y": 1]) == nil)
        #expect(EditorMessage(body: ["type": "linkMenu", "href": "https://example.com", "x": 1, "y": 1]) == nil)
        #expect(EditorMessage(body: ["type": "linkMenu", "href": "https://example.com", "openable": true, "x": 1]) == nil)
    }

    @Test func theMenuOffersOpenCopyEditAndRemoveForTheLinkItWasShownFor() {
        let target = NSObject()
        let scope = LinkMenu.Scope(href: "https://example.com", generation: 4, documentID: "memo")
        let action = #selector(NSObject.isEqual(_:))
        let menu = LinkMenu.make(for: scope, openable: true, target: target, open: action, copy: action, edit: action, remove: action)
        #expect(menu.items.map(\.title) == ["Open Link", "Copy Link", "", "Edit Link…", "Remove Link"])
        let items = menu.items.filter { !$0.isSeparatorItem }
        #expect(items.allSatisfy { $0.isEnabled && $0.target === target && $0.representedObject as? LinkMenu.Scope === scope })
    }

    @Test func anAddressTheAppWillNotOpenCanStillBeCopiedEditedAndRemoved() {
        let action = #selector(NSObject.isEqual(_:))
        let menu = LinkMenu.make(for: LinkMenu.Scope(href: "notes/today.md", generation: 1, documentID: "memo"), openable: false,
                                 target: NSObject(), open: action, copy: action, edit: action, remove: action)
        #expect(menu.items.filter { $0.isEnabled && !$0.isSeparatorItem }.map(\.title) == ["Copy Link", "Edit Link…", "Remove Link"])
        let empty = LinkMenu.make(for: LinkMenu.Scope(href: "", generation: 1, documentID: "memo"), openable: false,
                                  target: NSObject(), open: action, copy: action, edit: action, remove: action)
        #expect(empty.items.filter { $0.isEnabled && !$0.isSeparatorItem }.map(\.title) == ["Edit Link…", "Remove Link"])
    }
}
