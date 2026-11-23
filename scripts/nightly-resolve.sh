#!/usr/bin/env bash
# Step of job `check`: prints exactly one line `sha=<40 hex>` (for $GITHUB_OUTPUT) or fails with rc != 0 and prints NOTHING to stdout.
# Usage: nightly-resolve.sh SRC_DIR REF >> "$GITHUB_OUTPUT"
set -euo pipefail
sha=$("$(dirname "${BASH_SOURCE[0]}")/nightly-check-ref.sh" "${1:?usage: nightly-resolve.sh SRC_DIR REF}" "${2:?}")
echo "sha=$sha"
