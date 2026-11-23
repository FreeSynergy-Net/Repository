# shellcheck shell=bash disable=SC2154,SC2034
# Helpers of test_rpm.sh (sourced). Container only: throwaway key in $w, throwaway repo file, test stubs built here, never committed.
export CREATEREPO=${CREATEREPO:-createrepo_c} GNUPGHOME=$w/gh; mkdir -m700 "$GNUPGHOME"; fail=0; site=$w/site/rpm/stable
gpg --batch -q --passphrase '' --quick-gen-key "Test <t@example.invalid>" rsa3072 sign never 2> /dev/null
fpr=$(gpg --list-keys --with-colons | awk -F: '/^fpr:/ {print $10; exit}'); gpg --batch --armor --export "$fpr" > "$w/key.asc"; rpm --import "$w/key.asc"
printf '[t]\nname=t\nbaseurl=file://%s\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=file://%s/key.asc\n' "$site" "$w" > /etc/yum.repos.d/t.repo
ok() { echo "PASS: $1"; }; bad() { echo "FAIL: $1"; fail=1; }
sign() { "$here/sign-rpm.sh" --key "$fpr" "$1" "$2" > /dev/null; }
build() { rm -rf "$w/site"; sign packages "$1" && "$here/build-rpm.sh" "$1" stable "$w/site" > /dev/null && sign repo "$site"; }
inst() { dnf -q clean all > /dev/null 2>&1; dnf -y --disablerepo='*' --enablerepo=t --refresh install "$@" 2>&1; }
stub() { printf 'Name: fs-stub\nVersion: 9\nRelease: 1\nSummary: stub\nLicense: MIT\nBuildArch: noarch\nProvides: fs-starter = 9\nProvides: fs-module-board = 9\n%%description\nstub\n%%files\n' > "$w/s.spec"
  rpmbuild -bb --define "_topdir $w/rb" "$w/s.spec" > /dev/null 2>&1; cp "$w"/rb/RPMS/noarch/fs-stub*.rpm "$1/"; }
refused() { # NAME REGEX PKG: install must fail AND say why (REGEX in dnf output)
  local out rc; out=$(inst "$3"); rc=$?; echo "$out" | tail -6
  if [[ $rc != 0 ]] && grep -qiE "$2" <<< "$out"; then ok "$1 refused (rc $rc)"; else bad "$1 accepted or refused for another reason"; fi; }
