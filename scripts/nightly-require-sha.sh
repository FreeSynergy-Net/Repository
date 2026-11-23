#!/usr/bin/env bash
# Hard stop: the value must be a full 40-hex commit SHA (an empty value would check out the default branch at its current head).
# Usage: nightly-require-sha.sh VALUE      (used in job build BEFORE any checkout, and by nightly-resolve.sh)
set -euo pipefail
[[ ${1-} =~ ^[0-9a-f]{40}$ ]] || { echo "error: not a full commit SHA: '${1-}'" >&2; exit 1; }
