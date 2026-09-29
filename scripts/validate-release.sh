#!/bin/zsh
set -euo pipefail
cd "${0:a:h}/.."
tag="${1:-${CI_TAG:-}}"
[[ "$tag" =~ '^v[0-9]+\.[0-9]+\.[0-9]+$' ]] || {
  print -u2 'Release requires a vMAJOR.MINOR.PATCH tag.'
  exit 1
}
version=$(sed -n 's/^[[:space:]]*MARKETING_VERSION: "\([0-9.]*\)"/\1/p' project.yml)
[[ "${tag#v}" == "$version" ]] || {
  print -u2 "Tag $tag does not match project version $version."
  exit 1
}
print "Validated release $tag."
