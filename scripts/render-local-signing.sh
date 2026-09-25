#!/bin/zsh
set -euo pipefail
cd "${0:a:h}/.."

team="${APPLE_DEVELOPMENT_TEAM:-}"
[[ "$team" =~ '^[A-Z0-9]{10}$' ]] || {
  print -u2 -- 'APPLE_DEVELOPMENT_TEAM is missing or invalid; run this script through aic-infisical-run.'
  exit 1
}

mkdir -p Config
umask 077
temp=$(mktemp Config/Local.xcconfig.XXXXXX)
trap 'rm -f "$temp"' EXIT
{
  print -- 'CODE_SIGNING_ALLOWED = YES'
  print -- 'CODE_SIGN_STYLE = Automatic'
  print -- "DEVELOPMENT_TEAM = $team"
} > "$temp"
mv "$temp" Config/Local.xcconfig
print -- 'Rendered local signing configuration from Infisical.'
