#!/usr/bin/env bash
# Test of nightly-check-ref.sh with a fake source repo: main ok, main ancestor ok, commit only on a branch refused, branch name refused, tag name refused.
# shellcheck disable=SC2015
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd); w=$(mktemp -d); trap 'rm -rf "$w"' EXIT; fail=0; c=$here/nightly-check-ref.sh
g() { git -C "$w/o" -c user.name=t -c user.email=t@example.invalid "$@"; }
git init -q -b main "$w/o"; g commit -q --allow-empty -m a; a=$(g rev-parse HEAD); g commit -q --allow-empty -m b; b=$(g rev-parse HEAD)
g tag v0 "$a"
g checkout -q -b feat; g commit -q --allow-empty -m c; f=$(g rev-parse HEAD); g tag v1 "$f"; g checkout -q main
git clone -q "$w/o" "$w/s"; git -C "$w/s" fetch -q origin feat "refs/tags/v1:refs/tags/v1" "refs/tags/v0:refs/tags/v0"
ok() { echo "PASS: $1"; }; bad() { echo "FAIL: $1"; fail=1; }
[[ $("$c" "$w/s" main) == "$b" ]] && ok "main" || bad "main"
[[ $("$c" "$w/s" "$a") == "$a" ]] && ok "ancestor of main" || bad "ancestor"
"$c" "$w/s" "$f" 2> /dev/null && bad "branch-only commit accepted" || ok "commit only on a branch refused"
"$c" "$w/s" feat 2> /dev/null && bad "branch name accepted" || ok "branch name refused"
"$c" "$w/s" v1 2> /dev/null && bad "tag name accepted" || ok "tag name refused"
"$c" "$w/s" refs/tags/v1 2> /dev/null && bad "tag ref accepted" || ok "tag ref refused"
"$c" "$w/s" 0123456789012345678901234567890123456789 2> /dev/null && bad "unknown sha accepted" || ok "unknown sha refused"
"$c" "$w/s" v0 2> /dev/null && bad "tag on a main commit accepted" || ok "tag on a main commit refused"
r=$here/nightly-resolve.sh; wf=$here/../.github/workflows/nightly.yml
[[ $("$r" "$w/s" main) == "sha=$b" ]] && ok "resolve prints sha=<sha>" || bad "resolve main"
out=$("$r" "$w/s" 0123456789012345678901234567890123456789 2> /dev/null); rc=$?; [[ $rc != 0 && -z $out ]] && ok "unknown sha: rc!=0, nothing written" || bad "unknown sha not stopped (rc $rc, out '$out')"
out=$("$r" "$w/s" "" 2> /dev/null); rc=$?; [[ $rc != 0 && -z $out ]] && ok "empty ref: rc!=0, nothing written" || bad "empty ref not stopped"
: > "$w/go"; bash -e -c '"$1" "$2" feat >> "$3"' _ "$r" "$w/s" "$w/go" 2> /dev/null; [[ $? != 0 && ! -s $w/go ]] && ok "step form: GITHUB_OUTPUT stays empty, step fails" || bad "step form"
# the build guard: the real step text of nightly.yml, run with an empty and an unknown value and a good one
guard=$(awk '/Stop unless the verified commit/ {s=1} s && /run: \|/ {r=1; next} r && /^      - / {exit} r {sub(/^          /, ""); print}' "$wf")
[[ -n $guard ]] && ok "guard text found in nightly.yml" || bad "guard text not found"
SHA="" bash -c "$guard" > /dev/null 2>&1 && bad "build guard passes an empty SHA" || ok "build guard stops an empty SHA"
SHA="main" bash -c "$guard" > /dev/null 2>&1 && bad "build guard passes a branch name" || ok "build guard stops a non-SHA"
SHA="$b" bash -c "$guard" > /dev/null 2>&1 && ok "build guard passes a full SHA" || bad "build guard rejects a good SHA"
# second barrier in job sign (scripts/nightly-verify-built.sh) + its place in nightly.yml: before the first secret reference
v=$here/nightly-verify-built.sh; mkdir "$w/bd"
printf '%s\n' "$b" > "$w/bd/built-sha-x86_64.txt"; printf '%s\n' "$b" > "$w/bd/built-sha-aarch64.txt"
"$v" "$b" "$w/bd" 2 > /dev/null 2>&1 && ok "same SHA: sign goes on" || bad "same SHA rejected"
"$v" "$a" "$w/bd" 2 > /dev/null 2>&1 && bad "different SHA accepted" || ok "different SHA: stop"
"$v" "" "$w/bd" 2 > /dev/null 2>&1 && bad "empty expected SHA accepted" || ok "empty expected SHA: stop"
printf '' > "$w/bd/built-sha-aarch64.txt"; "$v" "$b" "$w/bd" 2 > /dev/null 2>&1 && bad "empty built SHA accepted" || ok "empty built SHA: stop"
printf '%s\n' "$a" > "$w/bd/built-sha-aarch64.txt"; "$v" "$b" "$w/bd" 2 > /dev/null 2>&1 && bad "one differing build accepted" || ok "one build differs: stop"
rm "$w/bd/built-sha-aarch64.txt"; "$v" "$b" "$w/bd" 2 > /dev/null 2>&1 && bad "missing build record accepted" || ok "missing build record: stop"
signjob=$(awk '/^  sign:$/ {s=1} s && /^  upload:$/ {exit} s {print}' "$wf")
first=$(grep -n 'secrets\.' <<< "$signjob" | head -1 | cut -d: -f1); gate=$(grep -n 'nightly-verify-built.sh' <<< "$signjob" | head -1 | cut -d: -f1)
[[ -n $gate && -n $first && $gate -lt $first ]] && ok "verify step stands before the first secret reference" || bad "verify step not before secrets (gate $gate, secret $first)"
grep -q 'needs: \[check, build\]' <<< "$signjob" && ok "sign needs check and build" || bad "sign does not need check"
exit $fail
