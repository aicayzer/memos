#!/bin/zsh
# Cuts a release: a Developer ID archive exported, notarized and stapled; a DMG, notarized and stapled too;
# an EdDSA-signed appcast; both uploaded to the updates bucket; a tag and a GitHub release with the DMG; and
# the Homebrew cask pointed at it.
#
# The version is MARKETING_VERSION in project.yml, so a release starts with a commit that bumps it; the
# build number is the commit count, which only ever grows. Sparkle's tools come with its package, under
# build/SourcePackages once the archive has resolved it.
#
# Needs, from the environment:
#   ASC_KEY_ID, ASC_ISSUER_ID   an App Store Connect API key for notarytool; the key file is
#                               ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8 unless ASC_KEY_PATH says
#   CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID   for wrangler, on the account that holds the bucket
# and, in the login keychain, the Developer ID Application certificate and the Sparkle key under the
# account named below; and gh signed in as someone who can push to the tap. RELEASING.md has the one-time setup.
#
#   scripts/release.sh [--notes FILE] [--dry-run]
#
# --dry-run builds, signs and notarizes from wherever the tree is, and publishes nothing.
set -euo pipefail

fail() { print -u2 -- "release: $*"; exit 1 }

notes_file=""
dry_run=false
while (( $# )); do
  case "$1" in
    --notes) [[ -n "${2:-}" ]] || fail "--notes needs a file"; notes_file="${2:a}"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    *) fail "unknown option $1" ;;
  esac
done
cd "${0:a:h}/.."

app_name=$(sed -n 's/^name: *//p' project.yml)
version=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml)
team=$(sed -n 's/^ *DEVELOPMENT_TEAM: *//p' project.yml)
build=$(git rev-list --count HEAD)
tag="v$version"
bucket="memos-updates"
download_prefix="https://memos.cyzr.me/"
sparkle_account="me.cyzr.memos"
tap="aicayzer/tap"
cask="memos"
sparkle_bin="build/SourcePackages/artifacts/sparkle/Sparkle/bin"
asc_key="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID:-}.p8}"

[[ -n "$version" ]] || fail "MARKETING_VERSION not found in project.yml"
# A dry run may come from any branch; a release comes from main as pushed.
if ! $dry_run; then
  [[ -z "$(git status --porcelain)" ]] || fail "the tree has uncommitted changes"
  [[ "$(git branch --show-current)" == main ]] || fail "release from main"
  git fetch -q --tags origin main
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "main is not at origin/main"
  if git rev-parse -q --verify "refs/tags/$tag" >/dev/null && [[ "$(git rev-parse "$tag^{commit}")" != "$(git rev-parse HEAD)" ]]; then
    fail "$tag exists on another commit; bump MARKETING_VERSION first"
  fi
fi
[[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]] || fail "ASC_KEY_ID and ASC_ISSUER_ID are needed"
[[ -r "$asc_key" ]] || fail "App Store Connect key not found at $asc_key"
$dry_run || [[ -n "${CLOUDFLARE_API_TOKEN:-}" && -n "${CLOUDFLARE_ACCOUNT_ID:-}" ]] || fail "CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID are needed"
$dry_run || command -v brew >/dev/null || fail "brew is needed for the cask"
identity=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*('"$team"')\)".*/\1/p' | head -1)
[[ -n "$identity" ]] || fail "no Developer ID Application certificate for $team"

notarize() {
  local result="$out/notary-$(basename "$1").plist"
  xcrun notarytool submit "$1" --key "$asc_key" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait --output-format plist > "$result"
  if [[ "$(plutil -extract status raw "$result")" != Accepted ]]; then
    xcrun notarytool log "$(plutil -extract id raw "$result")" --key "$asc_key" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" "$result.log" || true
    fail "notarization of $1 was not accepted; see $result.log"
  fi
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
plutil -create xml1 "$archive/ExportOptions.plist"
plutil -insert method -string developer-id "$archive/ExportOptions.plist"
plutil -insert signingStyle -string automatic "$archive/ExportOptions.plist"
plutil -insert teamID -string "$team" "$archive/ExportOptions.plist"
xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$archive/ExportOptions.plist" -exportPath "$export_dir" -quiet
app="$export_dir/$app_name.app"
[[ -d "$app" ]] || fail "export produced no app"
# Resolving the package for the archive is what puts Sparkle's tools here.
[[ -x "$sparkle_bin/generate_appcast" ]] || fail "Sparkle's tools are missing from $sparkle_bin"

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
assessment=$(spctl -a -t open --context context:primary-signature -v "$dmg" 2>&1 || true)
[[ "$assessment" == *accepted* ]] || fail "Gatekeeper does not accept the disk image: $assessment"

print -- "release: release notes"
notes="$out/$app_name-$version.md"
if [[ -n "$notes_file" ]]; then
  cp "$notes_file" "$notes"
else
  previous=$(git describe --tags --abbrev=0 2>/dev/null || true)
  git log --format='- %s' ${previous:+$previous..}HEAD > "$notes"
fi

print -- "release: appcast"
# The appcast in the bucket carries the earlier releases; generate_appcast adds this one to it. Only "none
# yet" may pass as an empty start: any other failure would publish a feed with the earlier releases gone.
http_status=$(curl -sS -o "$out/appcast.xml" -w '%{http_code}' "${download_prefix}appcast.xml" || true)
case "$http_status" in
  200) ;;
  404) rm -f "$out/appcast.xml" ;;
  *) fail "fetching the appcast gave $http_status" ;;
esac
# No deltas: earlier images are not kept here, so a delta would depend on which machine ran this.
"$sparkle_bin/generate_appcast" --account "$sparkle_account" --download-url-prefix "$download_prefix" --embed-release-notes --maximum-deltas 0 "$out"
# generate_appcast warns rather than fails when the keychain key is not the one behind SUPublicEDKey,
# and writes the item unsigned; installed apps would refuse it.
python3 - "$out/appcast.xml" "$build" <<'PY' || fail "the appcast item for build $build is missing or unsigned"
import re, sys
xml = open(sys.argv[1]).read()
items = re.findall(r"<item>.*?</item>", xml, re.S)
item = next((i for i in items if f"<sparkle:version>{sys.argv[2]}</sparkle:version>" in i), None)
sys.exit(0 if item and 'sparkle:edSignature="' in item else 1)
PY

if $dry_run; then
  print -- "release: dry run; $dmg and $out/appcast.xml are ready, nothing published"
  exit 0
fi

# The appcast goes up after everything it describes, since it is what installed apps act on, and every step
# before it can be run again; the cask comes after it, needing only the GitHub release.
print -- "release: uploading the disk image"
wrangler r2 object put "$bucket/$(basename "$dmg")" --file "$dmg" --remote --content-type application/x-apple-diskimage >/dev/null
curl -fsSI "${download_prefix}$(basename "$dmg")" >/dev/null || fail "the disk image is not being served"

print -- "release: tagging and releasing $tag"
git rev-parse -q --verify "refs/tags/$tag" >/dev/null || git tag -a "$tag" -m "$app_name $version"
git push -q origin "$tag"
# A run after a failure carries a fresh disk image, so an existing release takes it in place of the earlier one.
if gh release view "$tag" >/dev/null 2>&1; then
  gh release upload "$tag" "$dmg" --clobber >/dev/null
else
  gh release create "$tag" "$dmg" --title "$app_name $version" --notes-file "$notes"
fi

print -- "release: publishing the appcast"
wrangler r2 object put "$bucket/appcast.xml" --file "$out/appcast.xml" --remote --content-type application/xml >/dev/null
curl -fsS "${download_prefix}appcast.xml" | grep -q "<sparkle:version>$build</sparkle:version>" || fail "the served appcast does not list build $build"

# The cask points at the release's DMG on GitHub; it is audited as edited before anything is pushed.
print -- "release: homebrew cask"
brew tap | grep -qx "$tap" || brew tap "$tap" >/dev/null
tap_dir=$(brew --repo "$tap")
cask_file="$tap_dir/Casks/$cask.rb"
[[ -f "$cask_file" ]] || fail "no cask at $cask_file"
# The tap as pushed is the source of truth; an edit left by a failed run would stop the pull.
git -C "$tap_dir" checkout -q -- "Casks/$cask.rb"
git -C "$tap_dir" pull -q --ff-only
# The checksum of what GitHub serves, which is what the cask fetches, rather than of the local file.
dmg_sha=$(curl -fsSL "https://github.com/aicayzer/memos/releases/download/$tag/$(basename "$dmg")" | shasum -a 256 | cut -d' ' -f1)
[[ "$dmg_sha" == "$(shasum -a 256 "$dmg" | cut -d' ' -f1)" ]] || fail "the disk image on the release is not the one built here"
sed -i '' -e "s|^  version \".*\"|  version \"$version\"|" -e "s|^  sha256 \".*\"|  sha256 \"$dmg_sha\"|" "$cask_file"
grep -q "^  version \"$version\"" "$cask_file" && grep -q "^  sha256 \"$dmg_sha\"" "$cask_file" || fail "the cask did not take the version and checksum"
brew audit --cask --strict --online "$tap/$cask" || fail "the cask does not pass audit"
git -C "$tap_dir" diff --quiet -- "Casks/$cask.rb" || git -C "$tap_dir" commit -q -m "$cask $tag" -- "Casks/$cask.rb"
# Only gh's credentials, ahead of any the system keychain holds for GitHub; pushing nothing new is fine.
git -C "$tap_dir" -c credential.helper= -c credential.helper='!gh auth git-credential' push -q origin HEAD
print -- "release: $tag is out"
