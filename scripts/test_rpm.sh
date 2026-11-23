#!/usr/bin/env bash
# Gate for the rpm channel; runs in a throwaway Fedora container (test-rpm-container.sh). Helpers: rpm-gate-lib.sh.
# Usage: test_rpm.sh RPMDIR    Checks: dnf install works; tampered package, tampered repomd.xml and unsigned package are refused for the right reason.
# shellcheck disable=SC2015,SC1091,SC2154
set -uo pipefail
src=$1; here=$(cd "$(dirname "$0")" && pwd); w=$(mktemp -d); source "$here/rpm-gate-lib.sh"
mkdir "$w/in"; cp "$src"/*.rpm "$w/in/"; stub "$w/in"; pkg=$(rpm -qp --qf '%{NAME}' "$src"/fs-demo*.rpm)
build "$w/in" || bad "build/sign"; [[ -s $site/repodata/repomd.xml.asc ]] && ok "repomd.xml.asc present" || bad "repomd.xml.asc missing"
inst "$pkg" | tail -3; rpm -q "$pkg" > /dev/null && ok "dnf install $pkg" || bad "dnf install"; dnf -y -q remove "$pkg" > /dev/null 2>&1
printf 'X' | dd of="$(ls "$site"/fs-demo*.rpm)" bs=1 seek=2000 conv=notrunc 2> /dev/null; refused "tampered package" "checksum|digest|signature" "$pkg"
build "$w/in"; sed -i '0,/<revision>/s/<revision>/<revision>9/' "$site/repodata/repomd.xml"; refused "tampered repomd.xml" "repomd.xml GPG signature|Bad PGP" "$pkg"
mkdir "$w/un"; cp "$w"/in/*.rpm "$w/un/"; rpmsign --delsign "$w"/un/*.rpm > /dev/null 2>&1; rm -rf "$w/site"; "$here/build-rpm.sh" "$w/un" stable "$w/site" > /dev/null
gpg --batch --armor --detach-sign -o "$site/repodata/repomd.xml.asc" "$site/repodata/repomd.xml"; refused "unsigned package" "package is not signed" "$pkg"
exit "$fail"
