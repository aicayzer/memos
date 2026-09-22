#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/Library/pnpm:/opt/homebrew/bin:/usr/local/bin:$PATH"
mode="${1:---verify}"
xcodegen generate
xcodebuild -project Memos.xcodeproj -scheme Memos -configuration Debug -derivedDataPath build-preview \
  MEMOS_APP_IDENTIFIER=me.cyzr.memos.preview MEMOS_DISPLAY_NAME="Memos Preview" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
preview="$PWD/build-preview/Build/Products/Debug/Memos.app"
if [[ "$mode" == "--build-only" ]]; then exit 0; fi
# Only the preview from this build is stopped. The installed app and its data are independent.
pkill -f "$preview/Contents/MacOS/Memos" || true
open -n "$preview"
case "$mode" in
  --verify) pgrep -f "$preview/Contents/MacOS/Memos" ;;
  --logs|--telemetry) /usr/bin/log stream --info --predicate 'subsystem == "me.cyzr.memos.preview"' ;;
  --debug) lldb -p "$(pgrep -f "$preview/Contents/MacOS/Memos" | head -n 1)" ;;
  run) ;;
  *) echo "usage: $0 [run|--verify|--build-only|--logs|--telemetry|--debug]" >&2; exit 2 ;;
esac
