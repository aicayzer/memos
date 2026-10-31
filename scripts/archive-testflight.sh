#!/bin/zsh
set -euo pipefail
set +x
cd "${0:a:h}/.."
umask 077

build_number="${1:-}"
[[ "$build_number" =~ '^[1-9][0-9]*$' ]] || {
  print -u2 'usage: scripts/archive-testflight.sh BUILD_NUMBER'
  exit 2
}
team="${APPLE_DEVELOPMENT_TEAM:-}"
[[ "$team" =~ '^[A-Z0-9]{10}$' ]] || {
  print -u2 'Run through the credential manager to supply APPLE_DEVELOPMENT_TEAM.'
  exit 1
}
[[ ! -f Config/Cloud.xcconfig ]] || {
  print -u2 'Cloud signing configuration exists. Use a clean local archive checkout.'
  exit 1
}
profile="${APPLE_PROVISIONING_PROFILE:-}"
identity="${APPLE_DISTRIBUTION_IDENTITY:-Apple Distribution}"
installer_identity="${APPLE_INSTALLER_IDENTITY:-3rd Party Mac Developer Installer}"
output="build/TestFlight-$build_number"
[[ ! -e "$output" ]] || {
  print -u2 'This build output already exists. Inspect its archive/export before retrying with a new directory or build number.'
  exit 1
}
mkdir -p "$output"
# Selects and unlocks the dedicated signing keychain (MEMOS_SIGNING_KEYCHAIN) through the rendered configuration.
scripts/render-local-signing.sh --distribution
unset MEMOS_KEYCHAIN_PASSWORD

# Provisioning authenticates with the App Store Connect API key, never the Xcode account.
auth_flags=()
if [[ -n "${ASC_KEY_ID:-}" ]]; then
  [[ -n "${ASC_ISSUER_ID:-}" && -n "${ASC_PRIVATE_KEY:-}" ]] || {
    print -u2 'ASC_KEY_ID needs ASC_ISSUER_ID and ASC_PRIVATE_KEY from the credential manager.'
    exit 1
  }
  key_file=$(mktemp "${TMPDIR:-/tmp}/asc-key.XXXXXX")
  trap 'rm -f "$key_file"' EXIT
  print -r -- "$ASC_PRIVATE_KEY" > "$key_file"
  auth_flags=(-allowProvisioningUpdates -authenticationKeyPath "$key_file" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi
xcodegen generate > "$output/generation.log" 2>&1 || {
  print -u2 "Project generation failed; inspect $output/generation.log privately."
  exit 1
}

# Keep operational files private, but installed app resources must be readable by every user.
# The parent opens each log with its private umask before starting the build subshell.
if ! (
  umask 022
  # Package resource bundles need the team and certificate too; only the app target receives a profile.
  xcodebuild -quiet -project Memos.xcodeproj -scheme Memos -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$output/Memos.xcarchive" \
  -derivedDataPath "$output/DerivedData" CURRENT_PROJECT_VERSION="$build_number" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$team" CODE_SIGN_IDENTITY="$identity" \
  "${auth_flags[@]}" archive
) > "$output/archive.log" 2>&1; then
  print -u2 "Archive failed; inspect $output/archive.log privately."
  exit 1
fi
# A root-owned package can pass codesign yet fail App Store validation if resources are owner-only.
python3 - "$output/Memos.xcarchive" <<'PY_PERMISSIONS'
from pathlib import Path
import plistlib
import stat
import sys

archive = Path(sys.argv[1])
with (archive / "Info.plist").open("rb") as file:
    properties = plistlib.load(file)["ApplicationProperties"]
app = archive / "Products" / properties["ApplicationPath"]
if not app.is_dir():
    raise SystemExit("Archived application is missing; refusing export.")
invalid = []
for path in [app, *app.rglob("*")]:
    if path.is_symlink():
        continue
    mode = stat.S_IMODE(path.stat().st_mode)
    required = stat.S_IROTH
    if path.is_dir() or mode & 0o111:
        required |= stat.S_IXOTH
    if mode & required != required:
        invalid.append(f"{path.relative_to(app)} ({mode:04o})")
if invalid:
    print("Archived app contains files inaccessible to installed users:", file=sys.stderr)
    print("\n".join(invalid), file=sys.stderr)
    raise SystemExit(1)
PY_PERMISSIONS
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleIdentifier' "$output/Memos.xcarchive/Info.plist")
python3 - "$output/ExportOptions.plist" "$team" "$profile" "$identity" "$installer_identity" "$bundle_id" <<'PY'
import plistlib, sys
path, team, profile, identity, installer, bundle = sys.argv[1:]
with open(path, 'wb') as file:
    plistlib.dump({
        'method': 'app-store-connect',
        'destination': 'export',
        'teamID': team,
        'signingStyle': 'manual',
        'signingCertificate': identity,
        'installerSigningCertificate': installer,
        'provisioningProfiles': {bundle: profile},
        'manageAppVersionAndBuildNumber': False,
    }, file)
PY
if ! (
  umask 022
  xcodebuild -quiet "${auth_flags[@]}" -exportArchive -archivePath "$output/Memos.xcarchive" \
  -exportPath "$output/Export" -exportOptionsPlist "$output/ExportOptions.plist"
) > "$output/export.log" 2>&1; then
  print -u2 "Export failed; inspect $output/export.log privately."
  exit 1
fi
print "Exported to $output/Export. Nothing was uploaded."
