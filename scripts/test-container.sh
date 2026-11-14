#!/usr/bin/env bash
# Run the self-test (and optionally the apt dry run) in a throwaway container. Local use only; never on a server.
# Usage: test-container.sh IMAGE [DEBDIR]      e.g. test-container.sh docker.io/library/debian:13 /path/with/debs
set -euo pipefail
image=${1:?usage: test-container.sh IMAGE [DEBDIR]}
debs=${2:-}
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
args=(run --rm -v "$root:/src:ro,z")
[[ -z $debs ]] || args+=(-v "$debs:/debs:ro,z")
podman "${args[@]}" "$image" bash -c '
  set -euo pipefail
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq > /dev/null
  apt-get install -y -qq --no-install-recommends apt-utils gnupg gpgv xz-utils > /dev/null
  cp -r /src /w && cd /w
  bash scripts/test_apt.sh 2>&1 | grep -v "^gpg:"
  if [[ -d /debs ]]; then bash scripts/dryrun-apt.sh /debs 2>&1 | grep -v "^gpg:"; fi
'
