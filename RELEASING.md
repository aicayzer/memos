# Releasing

The app ships through TestFlight and the App Store. The optional CLI ships separately as a Developer ID-signed, notarized archive on GitHub. Neither channel bundles the other executable.

## App preparation

Use Xcode 27 and macOS 27. `project.yml` is authoritative; check in the generated project, shared schemes, plist files, entitlements, and package lockfile. Regenerate with `xcodegen generate`; CI rejects differences. The `Memos` scheme archives only the app. `MemosTool` builds the standalone CLI.

For local development signing, inject the repository's existing credential-manager environment and run `scripts/render-local-signing.sh`. This renders ignored `Config/Local.xcconfig`; never edit it or commit signing identifiers. Development has its own bundle identifier, icon, preferences, library, and shortcuts.

Before shipping, run native and editor tests, then exercise memo editing, search/focus, storage conversion, shortcuts, Settings, and CLI access on an isolated test machine. Keep GUI suites serial and use disposable libraries. App Store delivery must also verify CLI access to the installed app's library; source-level shared store tests do not establish filesystem permission behavior.

## Xcode Cloud owner checklist

1. Register the existing app bundle identifier and create the App Store Connect app record. Keep its chosen locale. Enable Xcode Cloud through Product > Xcode Cloud > Create Workflow in Xcode, connecting the public repository and the shared `Memos` scheme.
2. Configure a Release workflow with Xcode 27, macOS 27, clean builds, and an **Archive — macOS** action using `Memos`, **TestFlight and App Store** distribution, and the scheme's Release configuration. Restrict workflow editing for App Store eligibility.
3. Set `APPLE_DEVELOPMENT_TEAM` in the workflow environment from the canonical credential-manager value. Do not substitute `CI_TEAM_ID`: it did not provide a valid signing team in the observed Cloud environment. The post-clone hook renders automatic signing, installs Node/pnpm for the bundled editor, and updates the build number from `CI_BUILD_NUMBER`.
4. Use a tag-change condition **begins with `v`** (the `v*` family). Remove branch, pull-request, and scheduled triggers. The hook requires a `vMAJOR.MINOR.PATCH` tag matching `MARKETING_VERSION`.
5. Set the next Cloud build number above every previously uploaded app build. Keep this counter monotonic. Add a **TestFlight Internal Testing** post-action for the intended internal group; do not enable external testing or public App Store submission.
6. After a green PR is squash merged, create the version-matching tag on main. Confirm the Cloud run uses that exact commit, successfully archives and uploads, and makes the processed build available to the internal group. Install the update through TestFlight on the isolated test machine and verify the installed version, app behavior, and library before marking delivery complete.

Apple references: [project requirements](https://developer.apple.com/documentation/xcode/setting-up-your-project-to-use-xcode-cloud), [distribution workflow](https://developer.apple.com/documentation/xcode/creating-a-workflow-that-builds-your-app-for-distribution), [build numbering](https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds), and [internal testing](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers).

## Manual TestFlight archive

When Cloud is unavailable, use an isolated checkout and the existing credential manager. Supply `APPLE_DEVELOPMENT_TEAM`, an installed `APPLE_PROVISIONING_PROFILE`, and the appropriate `APPLE_DISTRIBUTION_IDENTITY` and `APPLE_INSTALLER_IDENTITY`. An existing task keychain can be selected with `MEMOS_SIGNING_KEYCHAIN` and unlocked using injected `MEMOS_KEYCHAIN_PASSWORD`. Run:

```sh
scripts/archive-testflight.sh BUILD_NUMBER
scripts/upload-testflight.py build/TestFlight-BUILD_NUMBER/Export/Memos.pkg --wait
```

The upload requires injected `ASC_KEY_ID`, `ASC_ISSUER_ID`, and PEM `ASC_PRIVATE_KEY`. It renders a temporary private key, uploads, and removes that key. Logs stay private. The archive helper refuses existing output and verifies installed app file permissions before export. Check App Store Connect before retrying any uncertain upload. Advance Cloud's next build number afterward.

## Standalone CLI release

Release the CLI only after the corresponding installed app's create/read/update/delete behavior and CLI library access are verified. Public hosted CI builds the CLI unsigned and runs create/read/append/delete against a disposable library. No personal runner or signing secrets are exposed to public PRs.

On the isolated release machine, inject the existing mapped credential-manager environment. The CLI script needs `APPLE_DEVELOPMENT_TEAM`, an unlocked **Developer ID Application** certificate, `ASC_KEY_ID`, `ASC_ISSUER_ID`, and either PEM `ASC_PRIVATE_KEY` or an existing source-rendered `ASC_KEY_PATH`. Use `MEMOS_SIGNING_KEYCHAIN` to select a task keychain. No new hosted signing credentials are required.

```sh
scripts/release-cli.py
```

This builds the Release CLI for Apple silicon, signs it with hardened runtime and a secure timestamp, verifies the signature, creates the ZIP and checksum, and waits for Apple's notarization to return **Accepted**. A standalone executable cannot carry a stapled ticket; Gatekeeper retrieves its notarization record online. The private release directory contains the notarization result and logs. Nothing is published by default.

For publication, start from clean main matching origin/main, choose a new version in `project.yml`, and run the same script with `--publish --notes FILE` instead. It creates the separate `cli-v<version>` tag and GitHub release only after notarization succeeds. App tags use `v<version>`; CLI tags do not trigger the app's Cloud workflow. Output is never overwritten. If a release fails after a tag or upload, inspect that state and finish the existing release deliberately rather than replacing artifacts.

Download the published archive, compare `SHA256SUMS`, install its executable on the isolated test machine, and repeat the disposable library checks. Keep the app and CLI release evidence with the project records.
