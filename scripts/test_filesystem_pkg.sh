#!/usr/bin/env bash
# Self-test of check-filesystem-pkg.sh and of the gate unowned-dirs.sh for freesynergy-filesystem (INST-5). Fixtures are built with rpmbuild (no fs-blueprint needed).
# The good package must pass, each counter package (wrong in exactly one point) must be refused; a folder without an owner must turn the gate RED.
# shellcheck disable=SC2015,SC2016
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd); w=$(mktemp -d); trap 'rm -rf "$w"' EXIT; t=0; c=$here/check-filesystem-pkg.sh; u=$here/unowned-dirs.sh
ok() { echo "PASS: $1"; }; bad() { echo "FAIL: $1"; t=1; }
if ! { command -v rpmbuild > /dev/null && command -v rpm2cpio > /dev/null; }; then echo "SKIPPED: rpmbuild missing"; [[ -z ${CI:-} ]] || bad "rpm tools missing in CI"; exit $t; fi
L=/usr/libexec/freesynergy; S=/usr/share/freesynergy; SIX="$L $L/modules $S $S/frontends $S/modules $S/programs"
mk() { # NAME "DIRS (with optional %attr)" "FILES (path, optional)" [extra spec header]; -> $w/out/NAME-1-1.noarch.rpm
  local d f; mkdir -p "$w/out" "$w/rt"; d=$(for x in $2; do echo "%dir $x"; done); f=$(for x in $3; do echo "$x"; done)
  printf 'Name: %s\nVersion: 1\nRelease: 1\nSummary: t\nLicense: MIT\nBuildArch: noarch\n%b%%description\nt\n%%install\nfor p in %s %s; do mkdir -p %%{buildroot}$(dirname $p); done\nfor p in %s; do mkdir -p %%{buildroot}$p; done\nfor p in %s; do touch %%{buildroot}$p; done\n%%files\n%s\n%s\n%b' \
    "$1" "${HDR:-}" "${3:-/x}" "/x" "$2" "${3:-}" "$d" "$f" "${TAIL:-}" > "$w/$1.spec"
  rpmbuild -bb --define "_topdir $w/rt" "$w/$1.spec" > /dev/null 2>&1; cp "$w/rt/RPMS/noarch/$1-1-1.noarch.rpm" "$w/out/" || bad "fixture $1 not built"; }
good() { mkdir -p "$w/g"; rm -f "$w/g"/*; cp "$w/out/$1-1-1.noarch.rpm" "$w/g/"; }
mk freesynergy-filesystem "$SIX" ""
"$c" "$w/out/freesynergy-filesystem-1-1.noarch.rpm" > /dev/null && ok "good freesynergy-filesystem passes" || bad "good package refused"
refuse() { "$c" "$w/out/$1-1-1.noarch.rpm" 2> /dev/null && bad "$2 accepted" || ok "$2 refused"; }
mk freesynergy-filesystem-x "$SIX" ""; refuse freesynergy-filesystem-x "other package name"
mk freesynergy-filesystem "${SIX/$S\/programs/}" ""; refuse freesynergy-filesystem "package without one of the six folders"
mk freesynergy-filesystem "$SIX $S/extra" ""; refuse freesynergy-filesystem "package with a seventh folder"
mk freesynergy-filesystem "$SIX" "$S/programs/evil"; refuse freesynergy-filesystem "package with a file"
HDR='Requires: sudo\n' mk freesynergy-filesystem "$SIX" ""; refuse freesynergy-filesystem "package with Requires: sudo"
TAIL='%post\ntrue\n' mk freesynergy-filesystem "$SIX" ""; refuse freesynergy-filesystem "package with a %post scriptlet"
mk freesynergy-filesystem "$SIX" ""; sed -i "s|^%dir $S/programs|%attr(0777,root,root) %dir $S/programs|" "$w/freesynergy-filesystem.spec"
rpmbuild -bb --define "_topdir $w/rt" "$w/freesynergy-filesystem.spec" > /dev/null 2>&1; cp "$w/rt/RPMS/noarch/freesynergy-filesystem-1-1.noarch.rpm" "$w/out/"; refuse freesynergy-filesystem "folder mode 0777"
# gate unowned-dirs.sh: a module package alone leaves its parents unowned (RED); together with freesynergy-filesystem (Requires) nothing is unowned (GREEN)
mk freesynergy-filesystem "$SIX" ""
HDR='Requires: freesynergy-filesystem\n' mk fs-module-demo "$L/modules/demo" "$L/modules/demo/service"
good fs-module-demo; r=$("$u" "$w/g"); grep -q "UNOWNED fs-module-demo-1-1.noarch.rpm: $L/modules" <<< "$r" && ok "gate RED: folder without owner (module without freesynergy-filesystem)" || bad "gate did not find the unowned parent folder: $r"
cp "$w/out/freesynergy-filesystem-1-1.noarch.rpm" "$w/g/"; r=$("$u" "$w/g"); [[ -z $r ]] && ok "gate GREEN: module + freesynergy-filesystem, nothing unowned" || bad "gate not empty: $r"
HDR='Requires: freesynergy-filesystem\n' mk fs-module-nodir "" "$L/modules/nodir/service"; rm -f "$w/g"/*; cp "$w/out/fs-module-nodir-1-1.noarch.rpm" "$w/out/freesynergy-filesystem-1-1.noarch.rpm" "$w/g/"
r=$("$u" "$w/g"); grep -q "UNOWNED fs-module-nodir-1-1.noarch.rpm: $L/modules/nodir" <<< "$r" && ok "gate RED: own folder without %dir is named" || bad "own unowned folder not found: $r"
exit $t
