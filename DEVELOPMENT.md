# Development

## Requirements

Xcode 27 or later, XcodeGen, Node.js and pnpm.

## Build and run

- `scripts/build_and_run.sh` builds and opens the isolated Debug app (Memos Dev). `--build-only` skips opening it, and `--verify` also checks that it stays running.
- `xcodegen generate` regenerates `Memos.xcodeproj` from `project.yml`. Commit both.
- In `editor/`: `pnpm install --frozen-lockfile`, `pnpm typecheck`, `pnpm test`, `pnpm build`.

The app build bundles the editor offline. The pre-build script rebuilds it only when a file in `editor/` is newer than `editor/dist/index.html`, so several `xcodebuild` calls in one run build it once.

## Test plans

The `Memos` scheme has two test plans and the `Memos UI Tests` scheme has one. Each sets a time allowance per test, so a hung test fails instead of holding the run.

| Plan | Runs | Per-test allowance |
| --- | --- | --- |
| `Unit` (default) | Every `MemosTests` suite. The suites that open windows skip themselves, so a local run puts nothing on screen. | 60 s (maximum 120 s) |
| `Full` | The same suites with `MEMOS_WINDOW_TESTS=1`, so the window suites run. CI runs this plan. | 120 s (maximum 240 s) |
| `UI` | `MemosUITests` | 180 s (maximum 300 s) |

```sh
xcodebuild -project Memos.xcodeproj -scheme Memos -configuration Debug -destination 'platform=macOS' \
  -testPlan Unit CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= test
```

Use `-testPlan Full` to include the window suites, which open windows on the screen.

### UI tests

UI tests take over the screen, the keyboard and the clipboard. Run them only in an isolated session, never on a workstation in use. They fail at once unless `TEST_RUNNER_MEMOS_UI_TESTS=1` is set. They also check that the app under test is the Debug build (`me.cyzr.memos.dev`) and that its store folder is new.

```sh
TEST_RUNNER_MEMOS_UI_TESTS=1 xcodebuild -project Memos.xcodeproj -scheme 'Memos UI Tests' -configuration Debug \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= test
```

A test that needs another app in front, such as the global shortcut test, activates Finder with AppKit and sends the key to it without querying Finder first. Every XCTest event costs about 10 seconds while the Memos editor runs, because the web view never goes idle, so keep the number of typed and keyed steps in a test small. Posting a `CGEvent` would avoid the wait, but the test runner has no Accessibility grant to post one.

## Continuous integration

Pull requests run `.github/workflows/ci.yml` on hosted workers. Pushes to `main` do not run it, because branch protection requires an up-to-date branch, so the merged tree is the tested tree. You can start it by hand with `workflow_dispatch`.

| Job | Runs on | What it checks |
| --- | --- | --- |
| `Changes` | Linux | `scripts/ci-scope.mjs` reads the diff. A change to only prose, `design/`, `marfa/`, `.codex/` or `.gitignore` runs no lane below. |
| `Editor` | Linux | Format, typecheck, tests and build of `editor/` |
| `App` | macOS | Generated project is current, build, `Full` plan, Release build, command line tool |
| `UI` | macOS | `UI` plan |
| `CI result` | Linux | The one required check. It passes when every lane succeeded or was skipped by scope. |

A new push cancels the running checks of its pull request. A draft pull request runs only `Editor`; mark it ready to run the rest. Logs and result bundles upload only on failure and expire after 7 days. Test screenshots and hierarchies are kept only for tests that fail.

### Run times

Before this policy (30 October 2026):

- A pull request ran one `Editor` job, then one `App` job of about 12 minutes, and `main` ran the same again for about 11 minutes.
- The editor built about 5 times per `App` run.
- The global shortcut test spent about 30 seconds waiting for idle after its keys.
- `EditorPolishTests` never ran, because the window gate was set for other suites only.
