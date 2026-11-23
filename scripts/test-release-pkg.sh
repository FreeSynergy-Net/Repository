#!/usr/bin/env bash
# First-contact gate for freesynergy-release (throwaway Fedora container, throwaway key; never on a server). Order of a user:
# shellcheck disable=SC2015
# fetch key from the Pages URL -> compare fingerprint -> rpm --import -> ONLY THEN dnf install. Without import and with a wrong fingerprint it must fail.
# Usage: test-release-pkg.sh FS_BLUEPRINT_BINARY [IMAGE]      (binary from the pinned fs-release, built by cargo; Rust first, no rpmbuild)
set -euo pipefail
if [[ -z ${IN_GATE:-} ]]; then
  bp=$(readlink -f "${1:?usage: test-release-pkg.sh FS_BLUEPRINT_BINARY [IMAGE]}"); root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
  exec podman run --rm -e IN_GATE=1 -v "$root:/src:ro,z" -v "$bp:/bin/fs-blueprint:ro,z" "${2:-registry.fedoraproject.org/fedora:45}" bash /src/scripts/test-release-pkg.sh
fi
dnf -y -q install rpm-sign gnupg2 curl python3 > /dev/null 2>&1; cp -r /src /w; cd /w; export GNUPGHOME=/gh U=http://127.0.0.1:8099/Repository; mkdir -m700 /gh; t=0
ok() { echo "PASS: $1"; }; bad() { echo "FAIL: $1"; t=1; }
gpg --batch -q --passphrase '' --quick-gen-key "Test <t@example.invalid>" rsa3072 sign never 2> /dev/null
fpr=$(gpg --list-keys --with-colons | awk -F: '/^fpr:/ {print $10; exit}'); gpg --batch --armor --export "$fpr" > /raw.asc
mkdir -p /site/Repository/rpm /rel; scripts/pubkey.sh /raw.asc "$fpr" /site/Repository/rpm/RPM-GPG-KEY-freesynergy
fs-blueprint package release --key /raw.asc --pages-url "$U" --out /rel > /dev/null && scripts/sign-rpm.sh --key "$fpr" packages /rel > /dev/null || bad "build/sign"
cp /rel/*.rpm /site/Repository/rpm/freesynergy-release.noarch.rpm; (cd /site && python3 -m http.server 8099 --bind 127.0.0.1 > /dev/null 2>&1 &); sleep 2
out=$(dnf -y --setopt=localpkg_gpgcheck=1 install "$U/rpm/freesynergy-release.noarch.rpm" 2>&1) && bad "installed WITHOUT key import" || { grep -qiE "signature|gpg|key" <<< "$out" && ok "no import: install refused"; } || bad "refused for another reason: $out"
curl -fsS "$U/rpm/RPM-GPG-KEY-freesynergy" -o /got.asc; got=$(gpg --show-keys --with-colons /got.asc | awk -F: '/^fpr:/ {print $10; exit}')
[[ $got == "AAAA${fpr:4}" ]] && bad "wrong fingerprint matched" || ok "wrong fingerprint: comparison fails"
[[ $got == "$fpr" ]] && ok "fingerprint of the fetched key equals the expected one" || bad "fingerprint differs"
rpm --import /got.asc && dnf -y --setopt=localpkg_gpgcheck=1 install "$U/rpm/freesynergy-release.noarch.rpm" > /dev/null 2>&1 && rpm -q freesynergy-release && grep -q "baseurl=$U/rpm/stable" /etc/yum.repos.d/freesynergy.repo && ok "import then install" || bad "import then install"
exit $t
