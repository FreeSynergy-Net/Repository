#!/usr/bin/env bash
# Test of nightly-check-ref.sh with a fake source repo: main ok, main ancestor ok, commit only on a branch refused, branch name refused, tag name refused.
# shellcheck disable=SC2015
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd); w=$(mktemp -d); trap 'rm -rf "$w"' EXIT; fail=0; c=$here/nightly-check-ref.sh
g() { git -C "$w/o" -c user.name=t -c user.email=t@example.invalid "$@"; }
git init -q -b main "$w/o"; g commit -q --allow-empty -m a; a=$(g rev-parse HEAD); g commit -q --allow-empty -m b; b=$(g rev-parse HEAD)
g checkout -q -b feat; g commit -q --allow-empty -m c; f=$(g rev-parse HEAD); g tag v1 "$f"; g checkout -q main
git clone -q "$w/o" "$w/s"; git -C "$w/s" fetch -q origin feat "refs/tags/v1:refs/tags/v1"
ok() { echo "PASS: $1"; }; bad() { echo "FAIL: $1"; fail=1; }
[[ $("$c" "$w/s" main) == "$b" ]] && ok "main" || bad "main"
[[ $("$c" "$w/s" "$a") == "$a" ]] && ok "ancestor of main" || bad "ancestor"
"$c" "$w/s" "$f" 2> /dev/null && bad "branch-only commit accepted" || ok "commit only on a branch refused"
"$c" "$w/s" feat 2> /dev/null && bad "branch name accepted" || ok "branch name refused"
"$c" "$w/s" v1 2> /dev/null && bad "tag name accepted" || ok "tag name refused"
"$c" "$w/s" refs/tags/v1 2> /dev/null && bad "tag ref accepted" || ok "tag ref refused"
"$c" "$w/s" 0123456789012345678901234567890123456789 2> /dev/null && bad "unknown sha accepted" || ok "unknown sha refused"
exit $fail
