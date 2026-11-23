#!/usr/bin/env bash
# `rpm -K` exits 0 for an UNSIGNED package ("digests OK"); a verified signature prints "digests signatures OK". Require that text for every file.
# Usage: check-rpm-signed.sh [--dbpath DIR] RPM...      (the key must be imported into that rpm database first)
set -euo pipefail
db=(); if [[ ${1-} == --dbpath ]]; then db=(--dbpath "${2:?usage: check-rpm-signed.sh [--dbpath DIR] RPM...}"); shift 2; fi
[[ $# -ge 1 ]] || { echo "usage: check-rpm-signed.sh [--dbpath DIR] RPM..." >&2; exit 2; }
for f in "$@"; do
  out=$(LC_ALL=C rpm "${db[@]}" -K "$f" 2>&1) || true
  grep -q 'digests signatures OK' <<< "$out" || { echo "error: signature not verified: $f ($out)" >&2; exit 1; }
done
