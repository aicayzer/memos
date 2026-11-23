import AppKit

/// What the person is offered on a link, in place of the web view's own items, which would try to load it here.
enum LinkMenu {
    final class Scope: NSObject {
        let href: String
        let generation: Int
        let documentID: String
        init(href: String, generation: Int, documentID: String) {
            self.href = href
            self.generation = generation
            self.documentID = documentID
        }
    }

    static func make(for scope: Scope, openable: Bool, target: AnyObject,
                     open: Selector, copy: Selector, edit: Selector, remove: Selector) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ title: String, _ action: Selector, enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = target
            item.representedObject = scope
            item.isEnabled = enabled
            menu.addItem(item)
        }
        add("Open Link", open, enabled: openable)
        add("Copy Link", copy, enabled: !scope.href.isEmpty)
        menu.addItem(.separator())
        add("Edit Link…", edit)
        add("Remove Link", remove)
        return menu
    }
}
