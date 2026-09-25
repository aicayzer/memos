# Releasing

A release is a Developer ID-signed, notarized app on a DMG, listed in an EdDSA-signed appcast that the app checks through [Sparkle](https://sparkle-project.org). `scripts/release.sh` does the whole run; what follows is the one-time setup it relies on and the routine.

## One-time setup

- **Developer ID Application certificate** for the team provided by Infisical, in the login keychain. Run `aic-infisical-run -- scripts/render-local-signing.sh` (or inject this project's Infisical development environment by another supported method) before building or releasing. This writes the ignored `Config/Local.xcconfig`; without it, the app builds unsigned.
- **App Store Connect API key** with the Developer role, for notarization: the `.p8` at `~/.appstoreconnect/private_keys/AuthKey_<key id>.p8` (or wherever `ASC_KEY_PATH` points), with `ASC_KEY_ID` and `ASC_ISSUER_ID` in the environment.
- **Sparkle signing key** in the login keychain under the account `me.cyzr.memos`, backed up as `SPARKLE_PRIVATE_KEY` in the mapped Infisical project's `dev` environment. Use Sparkle's `generate_keys --account me.cyzr.memos -p` to check the existing public key against `SUPublicEDKey` in `project.yml`. Preserve that key: installed apps cannot verify updates signed by a replacement. Export with `-x` only to a private temporary file, verify a backup before removing any old copy, and never commit or print the private key.
- **The updates bucket**, a Cloudflare R2 bucket named `memos-updates` behind `memos.cyzr.me`, which is `SUFeedURL`'s host. `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` in the environment give `wrangler` the account.
- `gh` signed in to an account that can create releases on the repository and push to the tap.
- **The Homebrew tap**, [aicayzer/homebrew-tap](https://github.com/aicayzer/homebrew-tap), whose `Casks/memos.rb` the script points at each release's DMG; the script taps it if `brew` has not.

## Cutting a release

1. Bump `MARKETING_VERSION` in `project.yml`, commit and merge; the release is cut from `main` at `origin/main`.
2. Run `scripts/release.sh`, with `--notes FILE` for written release notes (otherwise the commit subjects since the last tag) and `--dry-run` to build, sign and notarize without publishing.

The script archives the app with the commit count as its build number, exports it with Developer ID signing (which re-signs the framework, its XPC services and the tool with the hardened runtime and a timestamp), notarizes and staples the app, builds the DMG and notarizes and staples that too, fetches the appcast from the bucket and adds the release to it with `generate_appcast`, uploads the DMG and the appcast, tags `v<version>`, creates the GitHub release with the DMG attached, and points the Homebrew cask at that DMG, audited before it is pushed. `releases/` holds the local copies and is ignored.

Installed apps ask once whether to check for updates automatically; **Check for Updates…** in the app menu, or in Settings' About tab, checks on demand. A Debug build carries no updater.
