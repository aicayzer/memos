<img src="App/Resources/AppIcon.png" width="128" alt="">

# Memos

A small native Mac app for memos: one window that floats above whatever you are doing, a memo filling it, edited as formatted text and stored as markdown. Keyboard first, system fonts and colors, nothing decorative.

A native window with a web editor inside it. The native side owns the window, the command palette, browsing, shortcuts and saving; the editor is a bundled web page that works offline.

## Using it

- A file dropped on the memo inserts its path where it lands.
- ⌘K command palette, ⌘P browse memos, ⌘N new, ⌘D duplicate, ⇧⌘F favorite, ⌘[ and ⌘] back and forward, ⌘F find, ⇧⌘C copy as markdown, ⇧⌘S saves the memo as a markdown file, and Share… in the File menu hands that file to another app.
- ⌃⌥N shows or hides the window from any app. A menu bar item and the Dock icon are the other ways in; either can be switched off in Settings, and both once a shortcut is set.
- A formatting bar floats at the bottom of the memo: headings, bold, italic, strikethrough, link, code, quote and lists, showing what the caret sits in. Its close button hides it, and the palette brings it back.
- ⌥⌘← (or ⌘.), or a double-click on the title bar, opens a side pane listing the memos with a search field; the window grows to the left to make room and shrinks back when it closes. Settings can open it at launch.
- The window takes the keyboard without bringing the app to the front, so the app you were in keeps the menu bar while you type; a Dock click brings up the Memos menus, whose Memo and Window items are also in the palette.
- Always on Top keeps it above other apps and on every space; the background, side pane and accent are set in Settings (⌘,), whose Shortcuts tab records the global show/hide shortcut and lets every other shortcut, the editor's included, be changed or given more keys.
- Type markdown as you go: `# `, `- `, `1. `, `- [ ] `, `> ` and backticks turn into formatting. ⌘-click opens a link.

## From the shell

The app carries a command line tool at `Contents/SharedSupport/bin/memos`; put a symlink to it on your PATH:

```sh
ln -s /Applications/Memos.app/Contents/SharedSupport/bin/memos ~/.local/bin/memos
```

It reads and writes the same store as the app, which picks up changes as they land.

```sh
memos                      # list, favorites first then newest
memos list plan            # memos whose title or text contains "plan"
memos show plan            # the markdown; a memo is named by id, the start of one, its title or the start of that
memos new "# Call the bank"
pbpaste | memos new
memos append plan "- ring back on Monday"
memos replace plan < notes.md
memos edit plan            # in $EDITOR
memos favorite plan
memos unfavorite plan
memos open plan            # shows the app on that memo
memos delete plan          # the app itself has no delete yet
memos path                 # the store file
```

`--json` on `list` and `show` gives every field. `MEMOS_STORE` in the environment points the tool at another store file.

## Build

Requires Xcode 26 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and [pnpm](https://pnpm.io). The app build looks for pnpm in `~/Library/pnpm`, `/opt/homebrew/bin` and `/usr/local/bin` as well as the PATH Xcode runs with.

```sh
xcodegen generate
xcodebuild -project Memos.xcodeproj -scheme Memos -configuration Debug build
```

The app icon is an Icon Composer document, `App/Resources/AppIcon.icon`, which Xcode compiles; `App/Resources/AppIcon.png` is the same icon rendered, for this page.

The editor is built by a run-script phase during the app build. To work on it alone:

```sh
cd editor
pnpm install
pnpm test
pnpm build
```

See `AGENTS.md` for conventions and `editor/BRIDGE.md` for the message protocol between the app and the editor.
