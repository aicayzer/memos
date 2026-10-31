#!/bin/zsh
set -euo pipefail
cd "${0:a:h}/.."
team="${APPLE_DEVELOPMENT_TEAM:-}"
[[ "$team" =~ '^[A-Z0-9]{10}$' ]] || {
  print -u2 'APPLE_DEVELOPMENT_TEAM must be supplied by the credential manager.'
  exit 1
}
mode="${1:-development}"
case "$mode" in
  development|--distribution) ;;
  *) print -u2 "usage: scripts/render-local-signing.sh [--distribution]"; exit 2 ;;
esac
if [[ "$mode" == --distribution ]]; then
  profile="${APPLE_PROVISIONING_PROFILE:-}"
  [[ -n "$profile" && "$profile" != *$'\n'* && "$profile" != *$'\r'* && "$profile" != *'//'* && "$profile" != *'$'* ]] || {
    print -u2 'APPLE_PROVISIONING_PROFILE must name an installed distribution profile.'
    exit 1
  }
fi
# A dedicated signing keychain, rendered by aic-signing-keychain, keeps codesign out of the login keychain.
keychain="${MEMOS_SIGNING_KEYCHAIN:-}"
if [[ -n "$keychain" ]]; then
  [[ -f "$keychain" && "$keychain" != *[\'$'\n'\\]* ]] || {
    print -u2 'MEMOS_SIGNING_KEYCHAIN must name an existing signing keychain.'
    exit 1
  }
  if [[ -n "${MEMOS_KEYCHAIN_PASSWORD:-}" ]]; then
    /usr/bin/security unlock-keychain -p "$MEMOS_KEYCHAIN_PASSWORD" "$keychain" > /dev/null 2>&1 || {
      print -u2 'Could not unlock the signing keychain; check its injected credentials.'
      exit 1
    }
  fi
fi
umask 077
temp=$(mktemp Config/Local.xcconfig.XXXXXX)
trap 'rm -f "$temp"' EXIT
{
  print 'CODE_SIGNING_ALLOWED = YES'
  print 'CODE_SIGN_STYLE = Automatic'
  print "DEVELOPMENT_TEAM = $team"
  [[ -z "$keychain" ]] || print "OTHER_CODE_SIGN_FLAGS = --keychain '$keychain'"
  if [[ "$mode" == --distribution ]]; then
    print 'MEMOS_DISTRIBUTION_SIGNING_STYLE = Manual'
    print "MEMOS_DISTRIBUTION_PROFILE = $profile"
  fi
} > "$temp"
mv "$temp" Config/Local.xcconfig
print 'Rendered local signing configuration.'
