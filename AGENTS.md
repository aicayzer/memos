# Memos

Little Memos is a native macOS memo app with a bundled InkKit editor, an optional command line tool and App Intents.

This file governs every session in this repository. Commands, test plans and CI are in [DEVELOPMENT.md](DEVELOPMENT.md); distribution is in [RELEASING.md](RELEASING.md). Do not repeat them here.

## Conventions

- American English in code, comments, commits and repository files.
- Scoped Conventional Commits, such as `feat(app):`, `fix(editor):` or `chore(ci):`. Present tense, lowercase, short.
- Work on a feature branch and open a pull request. Never push to `main`. Merge only when CI is green, as a squash merge, and delete the branch.
- A comment survives only if it carries a reason the code cannot show.
- No absolute paths, machine names, account names or credentials in any file here.
- No legacy: no compatibility shims, deprecation aliases or historical schema migrations. Explicit conversion between the two supported storage modes is a product feature. Removed means gone.
- Releases are patch releases, features included. Propose a minor bump and agree it first, only for something that demands it: a change to the store format or to how the app is installed.
- `project.yml` is the only place for the product name, display name and bundle identifier.
- Keep the README short and user-facing. Development procedures belong in DEVELOPMENT.md or RELEASING.md.

## Layout

- `project.yml` is the XcodeGen source. `Memos.xcodeproj` and the shared schemes are generated and committed for Xcode Cloud; regenerate and commit them together, because CI rejects differences.
- `Core/` holds the memo model and the store, compiled into the app and the command line tool. `App/` holds the rest of the app, with the icon under `App/Resources/`. `CLI/` is the tool.
- `Tests/` is the Swift Testing target and `UITests/` the XCTest UI target. `TestPlans/` holds the test plans, which `project.yml` wires into the schemes.
- `scripts/` holds the build, CI-scope and release scripts. `ci_scripts/` holds the Xcode Cloud hook. `Config/Signing.xcconfig` is committed; `Config/Local.xcconfig` is ignored local signing.
- `editor/` is the Vite host bootstrap for `@aicayzer/inkkit`, built into one offline HTML file during the app build. [editor/BRIDGE.md](editor/BRIDGE.md) defines the message protocol.

## Development builds

- Debug builds are **Memos Dev**, with a visible DEV label, `App/Resources/AppIconDEV.icon` and their own bundle identity, URL scheme, preferences and store. Release builds keep the standard name and icon. Keep this configuration in `project.yml`.
- Debug builds start with Always on top off; Release starts with it on. Debug global shortcuts are Control-Option-Command-B (toggle) and Control-Option-Command-M (new memo), so they do not collide with an installed copy.
- Build and open the Debug app with `scripts/build_and_run.sh`. It refuses to rebuild a running preview, which may be in use, so check before quitting it.
- Never replace or quit the installed app to test. `scripts/screenshots.sh` prepares sample content for screenshots; it is not the isolated launcher.
- Use disposable memos for UI checks.
- The checkout builds without a signing team. Local signing is rendered into the ignored `Config/Local.xcconfig` by `scripts/render-local-signing.sh`, as [RELEASING.md](RELEASING.md) describes. Never commit signing identifiers or hand-edit generated configuration.

## Testing

- A suite that opens a window carries the `.opensWindows` trait (`Tests/OpensWindows.swift`). It skips unless `MEMOS_WINDOW_TESTS=1`, so a local run of the `Unit` plan puts nothing on screen.
- UI tests and window suites take over the screen, keyboard and clipboard. Run them only in an isolated GUI session on a machine nobody is using, never on an occupied workstation. UI tests fail at once unless `TEST_RUNNER_MEMOS_UI_TESTS=1` is set.
- Unit tests do not prove window behavior; exercise changed focus, windows and shortcuts in a real session.
- Public pull requests use hosted CI only; never attach a persistent personal runner.

## Store

- `MemoStore` is implemented by `LibraryStore`, which selects internal JSON or Markdown files through a committed storage manifest. Settings converts the whole library, verifies it, then switches the manifest atomically.
- The app, the CLI and App Intents share this store and its lock.
- Keep the protocol small so another store can stand behind it. Do not add fields for sync, tags or folders.

## Distribution

- The app ships through TestFlight and the App Store with the Xcode Cloud Release workflow, triggered by `vX.Y.Z` tags on `main`. Use a manual archive only as a fallback, and keep Cloud's next build number above every uploaded build.
- The CLI is a separate signed, notarized download. Never embed it in the app.
- Do not restore a direct-app updater, TextPad code, document registration or transitional integration. Preserve existing library paths and bundle identities.
- A release is complete only after processing, internal tester availability and an installed smoke check.

## Shared editor integration

InkKit owns Markdown preservation, editable tables, clipboard conversion and optional managed images. Keep native storage and document lifecycle in this app. Await a fresh, scoped snapshot before any action that depends on current text; a script failure must retain the document and the clipboard. Consumer tests check the package facade, and engine regression tests belong in the InkKit repository.
