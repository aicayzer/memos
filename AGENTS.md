# Memos

This file governs every session that works in this repository.

## Conventions

- **American English** in code, comments, commits and repository files.
- **Scoped Conventional Commits**, for example `feat(app):`, `fix(editor):`, `chore(ci):`. Present tense, lowercase, short.
- **Feature branch plus pull request.** Never push to `main`. CI must be green before a merge; squash merge, branch deleted.
- **Comments explain why, not what.** A comment survives only if it carries a reason the code cannot. Keep them short.
- **No personal detail.** No absolute paths, machine names, account names or credentials in any file here.
- **No legacy.** No compatibility shims, no deprecation aliases, no historical schema migration paths. Explicit conversion between the two supported storage modes is a product feature. Removed means gone.
- **No time estimates.**
- **Releases are patch releases.** The patch number goes up, features included. A minor bump is proposed and agreed first, never assumed, and only for something that demands it: a change to the store format, or to how the app is installed.
- **The name lives in `project.yml`.** Product name, display name and bundle identifier are set there and nowhere else.

## Layout

- `project.yml` is the XcodeGen source; `Memos.xcodeproj` is generated and not committed. `scripts/release.sh` cuts a release as [RELEASING.md](RELEASING.md) describes.
- `Core/` holds the memo model and the store, compiled into the app and the command line tool alike; `App/` the rest of the app's Swift sources, with the icon under `App/Resources/`; `CLI/` the tool; `Tests/` the Swift Testing target.
- `editor/` is the web editor (Vite, TypeScript, Milkdown), built into a single offline HTML file during the app build. [editor/BRIDGE.md](editor/BRIDGE.md) defines the message protocol between the two.

## Commands

- Requires Xcode 27 or later, XcodeGen, and pnpm.
- `script/build_and_run.sh` builds and opens the isolated Debug app; `--build-only` skips opening it. Both refuse to rebuild a running preview. Check whether it is in use before quitting it and rerunning the script.
- `xcodegen generate`, then `xcodebuild -project Memos.xcodeproj -scheme Memos -configuration Debug build` or `test`.
- In `editor/`: `pnpm install`, `pnpm typecheck`, `pnpm test`, `pnpm build`, `pnpm format`.

## Development builds

- Debug builds use **Memos Dev**, a visible DEV label, and `App/Resources/AppIconDEV.icon`. Release builds retain the standard name and icon. Keep identity and icon configuration in `project.yml`.
- Development builds have their own bundle identity, URL scheme, preferences, and store. Use disposable notes for UI checks. Development global shortcuts are Control-Option-Command-B (toggle), Control-Option-Command-M (new memo), and Control-Option-Command-Shift-B (TextPad).
- Do not replace or quit the installed app for testing. `scripts/screenshots.sh` prepares sample content; it is not the isolated development launcher.
- The checkout builds without a signing team. For local signing, run `aic-infisical-run -- scripts/render-local-signing.sh`, then regenerate the project. The renderer writes ignored `Config/Local.xcconfig`; never commit signing identifiers or hand-edit generated configuration.
- Keep the README short and user-facing. Development procedures belong here or in the linked technical documents.

## Store

The store behind `MemoStore` is `LibraryStore`, selecting internal JSON or Markdown files through a committed storage manifest. Settings converts the whole library, verifies it, then switches the manifest atomically. App, CLI and App Intents use this same store and lock. Keep the protocol small, so another store can stand behind it, and do not add fields for sync, tags or folders.
