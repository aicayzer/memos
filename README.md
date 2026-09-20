# Memos

A small native Mac app for memos: one window that floats above whatever you are doing, a memo filling it, edited as formatted text and stored as markdown. Keyboard first, system fonts and colors, nothing decorative.

A native window with a web editor inside it. The native side owns the window, the command palette, browsing, shortcuts and saving; the editor is a bundled web page that works offline.

## Using it

- ⌘K command palette, ⌘P browse memos, ⌘N new, ⌘D duplicate, ⇧⌘F favorite, ⌘[ and ⌘] back and forward, ⌘F find, ⇧⌘C copy as markdown, ⇧⌘S saves the memo as a markdown file, and Share… in the File menu hands that file to another app.
- ⌃⌘S, or a double-click on the title bar, opens a side pane listing the memos with a search field; Settings can open it at launch.
- Always on Top in the Window menu keeps it above other apps and on every space; the global show/hide shortcut, background, and accent are set in Settings (⌘,).
- Type markdown as you go: `# `, `- `, `1. `, `- [ ] `, `> ` and backticks turn into formatting. ⌘-click opens a link.

## Build

Requires Xcode 26 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and [pnpm](https://pnpm.io).

```sh
xcodegen generate
xcodebuild -project Memos.xcodeproj -scheme Memos -configuration Debug build
```

The editor is built by a run-script phase during the app build. To work on it alone:

```sh
cd editor
pnpm install
pnpm test
pnpm build
```

See `AGENTS.md` for conventions and `editor/BRIDGE.md` for the message protocol between the app and the editor.
