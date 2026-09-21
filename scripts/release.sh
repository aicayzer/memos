#!/bin/zsh
# Cuts a release: a Developer ID archive exported, notarized and stapled; a DMG, notarized and stapled too;
# an EdDSA-signed appcast; both uploaded to the updates bucket; a tag and a GitHub release with the DMG.
#
# The version is MARKETING_VERSION in project.yml, so a release starts with a commit that bumps it; the
# build number is the commit count, which only ever grows. Sparkle's tools come with the package, so a
# build of the project must have resolved it (they sit under build/SourcePackages).
#
# Needs, from the environment:
#   ASC_KEY_ID, ASC_ISSUER_ID   an App Store Connect API key for notarytool; the key file is
#                               ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8 unless ASC_KEY_PATH says
#   CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID   for wrangler, on the account that holds the bucket
# and, in the login keychain, the Developer ID Application certificate and the Sparkle key under the
# account named below. RELEASING.md has the one-time setup.
#
#   scripts/release.sh [--notes FILE] [--dry-run]
#
# --dry-run builds, signs and notarizes from wherever the tree is, and publishes nothing.
set -euo pipefail
cd "${0:a:h}/.."

notes_file=""
dry_run=false
while (( $# )); do
  case "$1" in
    --notes) notes_file="$2"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    *) print -u2 -- "release: unknown option $1"; exit 1 ;;
  esac
done

app_name=$(sed -n 's/^name: *//p' project.yml)
version=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml)
team=$(sed -n 's/^ *DEVELOPMENT_TEAM: *//p' project.yml)
build=$(git rev-list --count HEAD)
tag="v$version"
bucket="memos-updates"
download_prefix="https://memos.cyzr.me/"
sparkle_account="me.cyzr.memos"
sparkle_bin="build/SourcePackages/artifacts/sparkle/Sparkle/bin"
asc_key="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID:-}.p8}"

fail() { print -u2 -- "release: $*"; exit 1 }

[[ -n "$version" ]] || fail "MARKETING_VERSION not found in project.yml"
# A dry run may come from any branch; a release comes from main as pushed.
if ! $dry_run; then
  [[ -z "$(git status --porcelain)" ]] || fail "the tree has uncommitted changes"
  [[ "$(git branch --show-current)" == main ]] || fail "release from main"
  git fetch -q origin main
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "main is not at origin/main"
  git rev-parse -q --verify "refs/tags/$tag" >/dev/null && fail "$tag exists; bump MARKETING_VERSION first"
fi
[[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]] || fail "ASC_KEY_ID and ASC_ISSUER_ID are needed"
[[ -r "$asc_key" ]] || fail "App Store Connect key not found at $asc_key"
$dry_run || [[ -n "${CLOUDFLARE_API_TOKEN:-}" && -n "${CLOUDFLARE_ACCOUNT_ID:-}" ]] || fail "CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID are needed"
[[ -x "$sparkle_bin/generate_appcast" ]] || fail "Sparkle's tools are missing; build the project once"
identity=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*('"$team"')\)".*/\1/p' | head -1)
[[ -n "$identity" ]] || fail "no Developer ID Application certificate for $team"

notarize() {
  xcrun notarytool submit "$1" --key "$asc_key" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait --output-format plist > "$out/notary-$(basename "$1").plist"
  [[ "$(plutil -extract status raw "$out/notary-$(basename "$1").plist")" == Accepted ]] || fail "notarization of $1 was not accepted; see $out"
}

out="releases"
mkdir -p "$out"
archive="build/$app_name.xcarchive"
export_dir="build/export"
rm -rf "$archive" "$export_dir"

print -- "release: archiving $app_name $version ($build)"
xcodegen generate -q
xcodebuild -project "$app_name.xcodeproj" -scheme "$app_name" -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build -archivePath "$archive" CURRENT_PROJECT_VERSION="$build" archive -quiet
# The export re-signs every nested item with the hardened runtime and a timestamp, which a plain build
# does not do for the framework, its services or the tool.
xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist scripts/ExportOptions.plist -exportPath "$export_dir" -quiet
app="$export_dir/$app_name.app"
[[ -d "$app" ]] || fail "export produced no app"

print -- "release: notarizing the app"
ditto -c -k --keepParent "$app" "$export_dir/$app_name.zip"
notarize "$export_dir/$app_name.zip"
xcrun stapler staple -q "$app"

print -- "release: building the disk image"
dmg="$out/$app_name-$version.dmg"
staging="$export_dir/dmg"
rm -rf "$staging" "$dmg"
mkdir -p "$staging"
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname "$app_name" -srcfolder "$staging" -ov -format UDZO "$dmg"
# Gatekeeper assesses the image by its own signature, not only the app's.
codesign --sign "$identity" --timestamp "$dmg"
notarize "$dmg"
xcrun stapler staple -q "$dmg"
spctl -a -t open --context context:primary-signature -v "$dmg" 2>&1 | grep -q accepted || fail "Gatekeeper does not accept the disk image"

print -- "release: release notes"
notes="$out/$app_name-$version.md"
if [[ -n "$notes_file" ]]; then
  cp "$notes_file" "$notes"
else
  previous=$(git describe --tags --abbrev=0 2>/dev/null || true)
  git log --format='- %s' ${previous:+$previous..}HEAD > "$notes"
fi

print -- "release: appcast"
# The appcast in the bucket carries the earlier releases; generate_appcast adds this one to it.
curl -fsS "${download_prefix}appcast.xml" -o "$out/appcast.xml" 2>/dev/null || rm -f "$out/appcast.xml"
"$sparkle_bin/generate_appcast" --account "$sparkle_account" --download-url-prefix "$download_prefix" --embed-release-notes "$out" >/dev/null

if $dry_run; then
  print -- "release: dry run; $dmg and $out/appcast.xml are ready, nothing published"
  exit 0
fi

print -- "release: uploading"
wrangler r2 object put "$bucket/$(basename "$dmg")" --file "$dmg" --remote --content-type application/x-apple-diskimage >/dev/null
wrangler r2 object put "$bucket/appcast.xml" --file "$out/appcast.xml" --remote --content-type application/xml >/dev/null
curl -fsSI "${download_prefix}appcast.xml" >/dev/null || fail "the appcast is not being served"

print -- "release: tagging and releasing $tag"
git tag -a "$tag" -m "$app_name $version"
git push -q origin "$tag"
gh release create "$tag" "$dmg" --title "$app_name $version" --notes-file "$notes"
print -- "release: $tag is out"
