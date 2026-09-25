#!/bin/zsh
set -euo pipefail
cd "${0:a:h}/.."

mode="${1:-run}"
case "$mode" in
  run|--build-only|--verify) ;;
  *) print -u2 'usage: script/build_and_run.sh [--build-only|--verify]'; exit 2 ;;
esac

xcodegen generate -q
mkdir -p build/Dev
xcodebuild -project Memos.xcodeproj -scheme Memos -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/Dev -showBuildSettings -json > build/Dev/settings.json
read -r app_id < <(python3 -c 'import json; print(next(x["buildSettings"]["PRODUCT_BUNDLE_IDENTIFIER"] for x in json.load(open("build/Dev/settings.json")) if x["target"] == "Memos"))')
app_path=$(python3 -c 'import json; s=next(x["buildSettings"] for x in json.load(open("build/Dev/settings.json")) if x["target"] == "Memos"); print(s["TARGET_BUILD_DIR"]+"/"+s["FULL_PRODUCT_NAME"])')
if [[ -n "$(/usr/bin/lsappinfo find bundleID="$app_id")" ]]; then
  print -u2 'The development preview is running. Check whether it is in use, then quit it before rebuilding.'
  exit 1
fi
signing=()
if [[ ! -f Config/Local.xcconfig ]]; then
  signing=(CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
fi
xcodebuild -project Memos.xcodeproj -scheme Memos -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/Dev "${signing[@]}" build -quiet
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app_path/Contents/Info.plist")" == "$app_id" ]]
print -- "Built: $app_path"
[[ "$mode" == --build-only ]] && exit 0
open -n "$app_path"
if [[ "$mode" == --verify ]]; then
  app_executable=$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$app_path/Contents/Info.plist")
  for attempt in {1..20}; do
    if pgrep -fx "$app_path/Contents/MacOS/$app_executable" >/dev/null; then
      print 'Development preview is running.'
      exit 0
    fi
    sleep 0.25
  done
  print -u2 'The development preview did not stay running.'
  exit 1
fi
