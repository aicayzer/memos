# Releasing

A release is a Developer ID-signed, notarized app on a DMG, listed in an EdDSA-signed appcast that the app checks through [Sparkle](https://sparkle-project.org). `scripts/release.sh` does the whole run; what follows is the one-time setup it relies on and the routine.

## One-time setup

- **Developer ID Application certificate** for the team in `project.yml`, in the login keychain.
- **App Store Connect API key** with the Developer role, for notarization: the `.p8` at `~/.appstoreconnect/private_keys/AuthKey_<key id>.p8` (or wherever `ASC_KEY_PATH` points), with `ASC_KEY_ID` and `ASC_ISSUER_ID` in the environment.
- **Sparkle signing key** in the login keychain under the account `me.cyzr.memos`. `generate_keys --account me.cyzr.memos` (in `build/SourcePackages/artifacts/sparkle/Sparkle/bin` after any build) makes one and prints the public half, which is `SUPublicEDKey` in `project.yml`. Keep a copy of the private key somewhere safe: without it, installed apps cannot verify a later update.
- **The updates bucket**, a Cloudflare R2 bucket named `memos-updates` behind `memos.cyzr.me`, which is `SUFeedURL`'s host. `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` in the environment give `wrangler` the account.
- `gh` signed in to an account that can create releases on the repository.

## Cutting a release

1. Bump `MARKETING_VERSION` in `project.yml`, commit and merge; the release is cut from `main` at `origin/main`.
2. Run `scripts/release.sh`, with `--notes FILE` for written release notes (otherwise the commit subjects since the last tag) and `--dry-run` to build, sign and notarize without publishing.

The script archives the app with the commit count as its build number, exports it with Developer ID signing (which re-signs the framework, its XPC services and the tool with the hardened runtime and a timestamp), notarizes and staples the app, builds the DMG and notarizes and staples that too, fetches the appcast from the bucket and adds the release to it with `generate_appcast`, uploads the DMG and the appcast, tags `v<version>` and creates the GitHub release with the DMG attached. `releases/` holds the local copies and is ignored.

Installed apps ask once whether to check for updates automatically; **Check for Updates…** in the app menu, or in Settings' About tab, checks on demand. A Debug build carries no updater.
