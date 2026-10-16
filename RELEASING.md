# Releasing

The app ships through TestFlight and the App Store. The optional CLI ships separately as a Developer ID-signed, notarized archive on GitHub. Neither channel bundles the other executable.

## App preparation

Use Xcode 27 and macOS 27. `project.yml` is authoritative; check in the generated project, shared schemes, plist files, entitlements, and package lockfile. Regenerate with `xcodegen generate`; CI rejects differences. The `Memos` scheme archives only the app. `MemosTool` builds the standalone CLI.

For local development signing, inject the repository's existing credential-manager environment and run `scripts/render-local-signing.sh`. This renders ignored `Config/Local.xcconfig`; never edit it or commit signing identifiers. Development has its own bundle identifier, icon, preferences, library, and shortcuts.

Before shipping, run native and editor tests, then exercise memo editing, search/focus, storage conversion, shortcuts, Settings, and CLI access on an isolated test machine. Keep GUI suites serial and use disposable libraries. App Store delivery must also verify CLI access to the installed app's library; source-level shared store tests do not establish filesystem permission behavior.

## Xcode Cloud

Xcode Cloud is configured for product **Memos** with the **Release** workflow:

- Tag changes and manual starts for tags beginning with `v`; no branch, pull-request, or scheduled starts.
- Xcode 27, macOS 27, and clean builds, with `APPLE_DEVELOPMENT_TEAM` set in the workflow environment.
- One **Archive macOS** action using the `Memos` scheme, **Any Mac**, and **App Store Connect** distribution.
- One **TestFlight Internal Testing** post-action for **Internal Testers**.

The post-clone hook validates the tag against `MARKETING_VERSION`, renders automatic signing, installs Node/pnpm for the bundled editor, and sets the build number from `CI_BUILD_NUMBER`. Keep Cloud's next build number above every uploaded build. As of October 16, 2026, the next number is **8**; the latest uploaded build is **0.4.7 (7)**.

To release the app:

1. Bump `MARKETING_VERSION` in `project.yml`, run `xcodegen generate`, and commit the generated files. Run `scripts/validate-release.sh vX.Y.Z` with the matching version.
2. Merge the PR after CI passes. Create the matching `vX.Y.Z` tag on main and push the tag.
3. Cloud archives, uploads, and distributes the build to internal testers. Confirm the Cloud run uses the tagged commit, then check App Store Connect for successful processing and availability to **Internal Testers**.
4. Install through TestFlight on the isolated test machine and verify the version, app behavior, and library before marking delivery complete.

Apple references: [project requirements](https://developer.apple.com/documentation/xcode/setting-up-your-project-to-use-xcode-cloud), [distribution workflow](https://developer.apple.com/documentation/xcode/creating-a-workflow-that-builds-your-app-for-distribution), [build numbering](https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds), and [internal testing](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers).

## Manual TestFlight fallback

Use a manual archive only when Cloud is unavailable, with an isolated checkout and the existing credential manager. Supply `APPLE_DEVELOPMENT_TEAM`, an installed `APPLE_PROVISIONING_PROFILE`, and the appropriate `APPLE_DISTRIBUTION_IDENTITY` and `APPLE_INSTALLER_IDENTITY`. An existing task keychain can be selected with `MEMOS_SIGNING_KEYCHAIN` and unlocked using injected `MEMOS_KEYCHAIN_PASSWORD`. Run:

```sh
scripts/archive-testflight.sh BUILD_NUMBER
scripts/upload-testflight.py build/TestFlight-BUILD_NUMBER/Export/Memos.pkg --wait
```

The upload requires injected `ASC_KEY_ID`, `ASC_ISSUER_ID`, and PEM `ASC_PRIVATE_KEY`. It renders a temporary private key, uploads, and removes that key. Logs stay private. The archive helper refuses existing output and verifies installed app file permissions before export. Check App Store Connect before retrying any uncertain upload. After a manual upload, raise Cloud's next build number above the uploaded number before the next Cloud release.

## Standalone CLI release

Release the CLI only after the corresponding installed app's create/read/update/delete behavior and CLI library access are verified. Public hosted CI builds the CLI unsigned and runs create/read/append/delete against a disposable library. No personal runner or signing secrets are exposed to public PRs.

On the isolated release machine, inject the existing mapped credential-manager environment. The CLI script needs `APPLE_DEVELOPMENT_TEAM`, an unlocked **Developer ID Application** certificate, `ASC_KEY_ID`, `ASC_ISSUER_ID`, and either PEM `ASC_PRIVATE_KEY` or an existing source-rendered `ASC_KEY_PATH`. Use `MEMOS_SIGNING_KEYCHAIN` to select a task keychain. No new hosted signing credentials are required.

```sh
scripts/release-cli.py
```

This builds the Release CLI for Apple silicon, signs it with hardened runtime and a secure timestamp, verifies the signature, creates the ZIP and checksum, and waits for Apple's notarization to return **Accepted**. A standalone executable cannot carry a stapled ticket; Gatekeeper retrieves its notarization record online. The private release directory contains the notarization result and logs. Nothing is published by default.

For publication, start from clean main matching origin/main, choose a new version in `project.yml`, and run the same script with `--publish --notes FILE` instead. It creates the separate `cli-v<version>` tag and GitHub release only after notarization succeeds. App tags use `v<version>`; CLI tags do not trigger the app's Cloud workflow. Output is never overwritten. If a release fails after a tag or upload, inspect that state and finish the existing release deliberately rather than replacing artifacts.

Download the published archive, compare `SHA256SUMS`, install its executable on the isolated test machine, and repeat the disposable library checks. Keep the app and CLI release evidence with the project records.
