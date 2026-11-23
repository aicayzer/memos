# Releasing

The app ships through TestFlight and the App Store. The optional CLI ships separately as a Developer ID-signed, notarized archive on GitHub. Neither channel bundles the other executable.

## App preparation

Use Xcode 27 and macOS 27. `project.yml` is authoritative; check in the generated project, shared schemes, plist files, entitlements, and package lockfile. Regenerate with `xcodegen generate`; CI rejects differences. The `Memos` scheme archives only the app. `MemosTool` builds the standalone CLI.

Development builds have their own bundle identifier, icon, preferences, library, and shortcuts. For signing, see [Signing](#signing).

Before shipping, run native and editor tests, then exercise memo editing, search/focus, storage conversion, shortcuts, Settings, and CLI access on an isolated test machine. Keep GUI suites serial and use disposable libraries. App Store delivery must also verify CLI access to the installed app's library; source-level shared store tests do not establish filesystem permission behavior.

## Xcode Cloud

Xcode Cloud is configured for product **Memos** with the **Release** workflow:

- Tag changes and manual starts for tags beginning with `v`; no branch, pull-request, or scheduled starts.
- **Latest Release** for both Xcode and macOS, and clean builds, with `APPLE_DEVELOPMENT_TEAM` set in the workflow environment. A pinned version stops working when Apple retires its image.
- One **Archive macOS** action using the `Memos` scheme, **Any Mac**, and **App Store Connect** distribution.
- One **TestFlight Internal Testing** post-action for **Internal Testers**.

If a run fails within seconds and shows no actions, open the run in App Store Connect. The run page names the cause, such as a retired Xcode and macOS combination, which the API doesn't report.

The post-clone hook validates the tag against `MARKETING_VERSION`, renders automatic signing, installs Node/pnpm for the bundled editor, and sets the build number from `CI_BUILD_NUMBER`. Before each release, check the latest uploaded build in App Store Connect and Cloud's next build number. Keep Cloud's next build number above every uploaded build.

To release the app:

1. Bump `MARKETING_VERSION` in `project.yml`, run `xcodegen generate`, and commit the generated files. Run `scripts/validate-release.sh vX.Y.Z` with the matching version.
2. Merge the PR after CI passes. Create the matching `vX.Y.Z` tag on main and push the tag.
3. The **Release** GitHub Actions workflow publishes the GitHub Release for the tag with generated notes. It fails if the tag does not match `MARKETING_VERSION` or is not on main. Cloud archives, uploads, and distributes the build to internal testers. Confirm the Cloud run uses the tagged commit, then check App Store Connect for successful processing and availability to **Internal Testers**.
4. Install through TestFlight on the isolated test machine and verify the version, app behavior, and library before marking delivery complete.

Apple references: [project requirements](https://developer.apple.com/documentation/xcode/setting-up-your-project-to-use-xcode-cloud), [distribution workflow](https://developer.apple.com/documentation/xcode/creating-a-workflow-that-builds-your-app-for-distribution), [build numbering](https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds), and [internal testing](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers).

## Signing

`scripts/render-local-signing.sh` writes the ignored `Config/Local.xcconfig` from variables that your credential manager supplies. Never edit or commit that file, and never commit signing identifiers.

| Variable | Use |
| --- | --- |
| `APPLE_DEVELOPMENT_TEAM` | Required. The signing team. |
| `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY` | The App Store Connect team API key, for provisioning and upload. |
| `MEMOS_SIGNING_KEYCHAIN`, `MEMOS_KEYCHAIN_PASSWORD` | Optional. A dedicated keychain for signing over SSH. |
| `APPLE_PROVISIONING_PROFILE`, `APPLE_DISTRIBUTION_IDENTITY`, `APPLE_INSTALLER_IDENTITY` | Manual archives only. The installed App Store profile, and certificate names if they differ from Apple Distribution and 3rd Party Mac Developer Installer. |

- **On a Mac that you're signed in to,** builds sign from the login keychain.
- **Over SSH,** the login keychain is locked, so name a dedicated keychain. The script unlocks the keychain and selects it with `OTHER_CODE_SIGN_FLAGS`. The keychain locks again in each new session, so build in the same credential-manager session. If the named keychain doesn't exist on the Mac, builds use the login keychain.

With the API key set, archive and export provision through the key instead of an Xcode account.

## Manual TestFlight fallback

Archive manually only when Xcode Cloud is unavailable, from an isolated checkout:

```sh
scripts/archive-testflight.sh BUILD_NUMBER
scripts/upload-testflight.py build/TestFlight-BUILD_NUMBER/Export/Memos.pkg --wait
```

The archive script refuses an existing output directory and checks that every file in the app is readable by all users before export. The upload script writes the key to a private temporary file, removes it, and keeps logs private. If an upload's result is unclear, check App Store Connect before you retry. After a manual upload, raise Xcode Cloud's next build number above the uploaded one before the next Cloud release.

## Standalone CLI release

Release the CLI only after the corresponding installed app's create/read/update/delete behavior and CLI library access are verified. Public hosted CI builds the CLI unsigned and runs create/read/append/delete against a disposable library. No personal runner or signing secrets are exposed to public PRs.

On the isolated release machine, inject the existing mapped credential-manager environment. The CLI script needs `APPLE_DEVELOPMENT_TEAM`, an unlocked **Developer ID Application** certificate, `ASC_KEY_ID`, `ASC_ISSUER_ID`, and either PEM `ASC_PRIVATE_KEY` or an existing source-rendered `ASC_KEY_PATH`. `MEMOS_SIGNING_KEYCHAIN` selects a dedicated keychain, as in [Signing](#signing). No hosted signing credentials are needed.

```sh
scripts/release-cli.py
```

This builds the Release CLI for Apple silicon, signs it with hardened runtime and a secure timestamp, verifies the signature, creates the ZIP and checksum, and waits for Apple's notarization to return **Accepted**. A standalone executable cannot carry a stapled ticket; Gatekeeper retrieves its notarization record online. The private release directory contains the notarization result and logs. Nothing is published by default.

For publication, start from clean main matching origin/main, choose a new version in `project.yml`, and run the same script with `--publish --notes FILE` instead. It creates the separate `cli-v<version>` tag and GitHub release only after notarization succeeds. App tags use `v<version>`; CLI tags do not trigger the app's Cloud workflow. Output is never overwritten. If a release fails after a tag or upload, inspect that state and finish the existing release deliberately rather than replacing artifacts.

Download the published archive, compare `SHA256SUMS`, install its executable on the isolated test machine, and repeat the disposable library checks. Keep the app and CLI release evidence with the project records.
