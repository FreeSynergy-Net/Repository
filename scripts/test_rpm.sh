#!/usr/bin/env bash
# Gate for the rpm channel. Runs in a throwaway Fedora container (see test-rpm-container.sh); throwaway key, never leaves the container.
# Usage: test_rpm.sh RPMDIR    (RPMDIR holds a test .rpm; the test package is never committed)
# Checks: build + sign; dnf install works; tampered package fails; tampered repomd.xml fails; unsigned package fails.
# shellcheck disable=SC2015
set -uo pipefail
src=${1:?usage: test_rpm.sh RPMDIR}; here=$(cd "$(dirname "$0")" && pwd); w=$(mktemp -d); fail=0
export GNUPGHOME=$w/gh; mkdir -m700 "$GNUPGHOME"
gpg --batch -q --passphrase '' --quick-gen-key "Test <t@example.invalid>" rsa3072 sign never 2>/dev/null
fpr=$(gpg --list-keys --with-colons | awk -F: '/^fpr:/ {print $10; exit}'); gpg --batch --armor --export "$fpr" > "$w/key.asc"
ok() { echo "PASS: $1"; }; bad() { echo "FAIL: $1"; fail=1; }
build() { rm -rf "$w/site"; "$here/sign-rpm.sh" --key "$fpr" packages "$1" > /dev/null && CREATEREPO=${CREATEREPO:-createrepo_c} "$here/build-rpm.sh" "$1" stable "$w/site" > /dev/null && "$here/sign-rpm.sh" --key "$fpr" repo "$w/site/rpm/stable" > /dev/null; }
repo() { cat > /etc/yum.repos.d/t.repo <<R
[t]
name=t
baseurl=file://$w/site/rpm/stable
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=file://$w/key.asc
R
}
inst() { dnf -q clean all > /dev/null 2>&1; dnf -y --disablerepo='*' --enablerepo=t --refresh install "$@" 2>&1; }
rpm --import "$w/key.asc"; repo
# Test-only stubs for the dependencies of the data package (fs-starter, fs-module-*); built here, never committed.
mkdir "$w/in"; cp "$src"/fs-demo*.rpm "$w/in/"; cp "$src"/freesynergy-release*.rpm "$w/in/" 2> /dev/null
printf 'Name: fs-stub\nVersion: 9\nRelease: 1\nSummary: stub\nLicense: MIT\nBuildArch: noarch\nProvides: fs-starter = 9\nProvides: fs-module-board = 9\n%%description\nstub\n%%files\n' > "$w/stub.spec"
rpmbuild -bb --define "_topdir $w/rb" "$w/stub.spec" > /dev/null 2>&1; cp "$w"/rb/RPMS/noarch/fs-stub*.rpm "$w/in/"
src=$w/in
build "$src" || bad "build/sign"
[[ -s $w/site/rpm/stable/repodata/repomd.xml.asc ]] && ok "repomd.xml.asc present" || bad "repomd.xml.asc missing"
pkg=$(rpm -qp --qf '%{NAME}' "$(ls "$src"/fs-demo*.rpm)")
out=$(inst "$pkg"); rc=$?; echo "$out" | tail -5; [[ $rc == 0 ]] && rpm -q "$pkg" > /dev/null && ok "dnf install $pkg" || bad "dnf install"
dnf -y -q remove "$pkg" > /dev/null 2>&1
for f in "$w"/site/rpm/stable/fs-demo*.rpm; do printf 'X' | dd of="$f" bs=1 seek=2000 conv=notrunc 2> /dev/null; done
out=$(inst "$pkg"); rc=$?; echo "$out" | tail -6; [[ $rc != 0 ]] && grep -qiE "signature|digest|gpg|checksum|download" <<< "$out" && ok "tampered package refused (rc $rc)" || bad "tampered package accepted"
build "$src"; sed -i '0,/<revision>/s/<revision>/<revision>9/' "$w/site/rpm/stable/repodata/repomd.xml" && grep -c "<revision>9" "$w/site/rpm/stable/repodata/repomd.xml"
out=$(inst "$pkg"); rc=$?; echo "$out" | tail -6; [[ $rc != 0 ]] && grep -qiE "signature|repomd|gpg|checksum|repo" <<< "$out" && ok "tampered repomd.xml refused (rc $rc)" || bad "tampered repomd.xml accepted"
rm -rf "$w/site" "$w/un"; mkdir "$w/un"; cp "$w"/in/*.rpm "$w/un/"; rpmsign --delsign "$w"/un/*.rpm > /dev/null 2>&1; "$here/build-rpm.sh" "$w/un" stable "$w/site" > /dev/null; gpg --batch --armor --detach-sign -o "$w/site/rpm/stable/repodata/repomd.xml.asc" "$w/site/rpm/stable/repodata/repomd.xml"
out=$(inst "$pkg"); rc=$?; echo "$out" | tail -4; [[ $rc != 0 ]] && grep -qiE "signature|gpg" <<< "$out" && ok "unsigned package refused (rc $rc)" || bad "unsigned package accepted"
exit $fail
