#!/usr/bin/env bash
# Second barrier, in job `sign` BEFORE the key is touched: every build recorded the commit it really checked out (built-sha-<arch>.txt); all of them must equal
# the SHA verified by job `check` (a full 40-hex SHA), and there must be at least one. Empty, different or missing = stop.
# Usage: nightly-verify-built.sh EXPECTED_SHA DIR [MIN_FILES=1]
set -euo pipefail
exp=${1-}; dir=${2:?usage: nightly-verify-built.sh EXPECTED_SHA DIR [MIN]}; min=${3:-1}
[[ $exp =~ ^[0-9a-f]{40}$ ]] || { echo "error: expected SHA from job check is not a full SHA: '$exp'" >&2; exit 1; }
n=0
for f in "$dir"/built-sha-*.txt; do
  [[ -f $f ]] || continue
  got=$(tr -d '[:space:]' < "$f")
  [[ $got =~ ^[0-9a-f]{40}$ && $got == "$exp" ]] || { echo "error: $(basename "$f") says '$got', verified commit is $exp" >&2; exit 1; }
  n=$((n + 1))
done
((n >= min)) || { echo "error: $n build records, need $min" >&2; exit 1; }
echo "built commit = verified commit $exp ($n builds)"
