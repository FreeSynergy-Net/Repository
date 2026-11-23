#!/usr/bin/env bash
# Self-test of pubkey.sh and verify-repomd.sh with throwaway keys (no secrets). Each check has a counter-check that must fail.
# shellcheck disable=SC2015
set -euo pipefail
w=$(mktemp -d); export GNUPGHOME=$w/gh; mkdir -m700 "$GNUPGHOME"; here=$(cd "$(dirname "$0")" && pwd); t=0
trap 'gpgconf --kill gpg-agent >/dev/null 2>&1 || true; rm -rf "$w"' EXIT
ok() { echo "PASS: $1"; }; bad() { echo "FAIL: $1"; t=1; }
for n in a b; do gpg --batch -q --passphrase '' --quick-gen-key "$n <$n@example.invalid>" ed25519 sign never 2> /dev/null; done
fa=$(gpg --list-keys --with-colons a@example.invalid | awk -F: '/^fpr:/ {print $10; exit}'); fb=$(gpg --list-keys --with-colons b@example.invalid | awk -F: '/^fpr:/ {print $10; exit}')
gpg --batch --armor --export "$fa" > "$w/a.asc"; gpg --batch --armor --export "$fa" "$fb" > "$w/ab.asc"; gpg --batch --armor --export-secret-keys "$fa" > "$w/sec.asc"
"$here/pubkey.sh" "$w/ab.asc" "$fa" "$w/o.asc" 2> /dev/null && bad "two primaries accepted" || ok "two primary keys refused"
"$here/pubkey.sh" "$w/a.asc" "$fb" "$w/o.asc" 2> /dev/null && bad "wrong fingerprint accepted" || ok "wrong fingerprint refused"
"$here/pubkey.sh" "$w/sec.asc" "$fa" "$w/o.asc" 2> /dev/null && bad "secret key accepted" || ok "secret key refused"
"$here/pubkey.sh" "$w/a.asc" "$fa" "$w/o.asc" && ok "exact key exported" || bad "exact key refused"
echo repomd > "$w/x.xml"; gpg --batch --armor --local-user "$fa" --detach-sign -o "$w/x.asc" "$w/x.xml"
"$here/verify-repomd.sh" "$w/o.asc" "$fa" "$w/x.xml" "$w/x.asc" && ok "signature matches the pinned key" || bad "good signature refused"
gpg --batch --armor --export "$fb" > "$w/b.asc"
"$here/verify-repomd.sh" "$w/b.asc" "$fb" "$w/x.xml" "$w/x.asc" 2> /dev/null && bad "foreign key accepted" || ok "key that did not sign refused"
"$here/verify-repomd.sh" "$w/o.asc" "$fb" "$w/x.xml" "$w/x.asc" 2> /dev/null && bad "wrong pin accepted" || ok "wrong pinned fingerprint refused"
echo tampered > "$w/x.xml"; "$here/verify-repomd.sh" "$w/o.asc" "$fa" "$w/x.xml" "$w/x.asc" 2> /dev/null && bad "tampered accepted" || ok "tampered repomd refused"
# check-rpm-signed.sh (S-R3: plain `rpm -K` accepts an UNSIGNED package) and check-release-pkg.sh (S-R6); needs rpmbuild + rpmsign (package rpm on Debian/Ubuntu)
if command -v rpmbuild > /dev/null && command -v rpmsign > /dev/null; then
  U=https://x.example/Repository; R=/etc/pki/rpm-gpg/RPM-GPG-KEY-freesynergy; Y=/etc/yum.repos.d/freesynergy.repo
  repof() { printf '[freesynergy]\nname=FreeSynergy (stable)\nbaseurl=%s/rpm/stable\nenabled=%s\ngpgcheck=%s\nrepo_gpgcheck=1\ngpgkey=file://%s\n\n[freesynergy-nightly]\nname=FreeSynergy (nightly, for testers)\nbaseurl=%s/rpm/nightly\nenabled=0\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=file://%s\n' "$1" "$2" "$3" "$R" "$1" "$R"; }
  mkrpm() { # NAME KEYFILE REPOFILE -> $w/NAME.rpm; env: EXTRA=/path (third file), UNC=1 (uncompressed payload), POST=1 (%post scriptlet)
    local xi; xi="mkdir -p %{buildroot}$(dirname "${EXTRA:-/x}"); touch %{buildroot}${EXTRA:-}"$'\n'
    mkdir -p "$w/rb/$1"; cp "$2" "$w/rb/$1/key"; cp "$3" "$w/rb/$1/repo"
    printf 'Name: %s\nVersion: 1\nRelease: 1\nSummary: t\nLicense: MIT\nBuildArch: noarch\n%s%%description\nt\n%%install\nmkdir -p %%{buildroot}/etc/pki/rpm-gpg %%{buildroot}/etc/yum.repos.d\ncp %s/key %%{buildroot}%s\ncp %s/repo %%{buildroot}%s\n%s%%files\n%s\n%s\n%s\n%s' \
      "$1" "${UNC:+%define _binary_payload w.ufdio$'\n'}" "$w/rb/$1" "$R" "$w/rb/$1" "$Y" "${EXTRA:+$xi}" "$R" "$Y" "${EXTRA:-}" "${POST:+%post$'\n'true$'\n'}" > "$w/$1.spec"; rpmbuild -bb --define "_topdir $w/rt" "$w/$1.spec" > /dev/null 2>&1; cp "$w"/rt/RPMS/noarch/"$1"-1-1.noarch.rpm "$w/$1.rpm"; }
  repof "$U" 1 1 > "$w/good.repo"; "$here/pubkey.sh" "$w/a.asc" "$fa" "$w/pa.asc"
  mkrpm good "$w/pa.asc" "$w/good.repo"
  s=$here/check-rpm-signed.sh; c=$here/check-release-pkg.sh
  "$s" "$w/good.rpm" 2> /dev/null && bad "UNSIGNED rpm accepted by check-rpm-signed" || ok "unsigned rpm refused (plain rpm -K says rc=$(rpm -K "$w/good.rpm" > /dev/null 2>&1; echo $?))"
  cp "$w/good.rpm" "$w/signed.rpm"; rpmsign --addsign --define "_gpg_name $fa" --define "_gpg_path $GNUPGHOME" "$w/signed.rpm" > /dev/null 2>&1
  "$s" --dbpath "$w/db" "$w/signed.rpm" 2> /dev/null && bad "signed rpm accepted without the key" || ok "signed rpm without imported key refused"
  rpm --dbpath "$w/db" --import "$w/pa.asc"; "$s" --dbpath "$w/db" "$w/signed.rpm" && ok "signed rpm with imported key accepted" || bad "good signed rpm refused"
  "$c" "$w/good.rpm" "$fa" "$U" > /dev/null && ok "release pkg: key, baseurl, gpgcheck as expected" || bad "good release pkg refused"
  repof "$U/x" 1 1 > "$w/b1.repo"; mkrpm b1 "$w/pa.asc" "$w/b1.repo"; "$c" "$w/b1.rpm" "$fa" "$U" 2> /dev/null && bad "wrong baseurl accepted" || ok "wrong baseurl refused"
  repof "$U" 1 0 > "$w/b2.repo"; mkrpm b2 "$w/pa.asc" "$w/b2.repo"; "$c" "$w/b2.rpm" "$fa" "$U" 2> /dev/null && bad "gpgcheck=0 accepted" || ok "gpgcheck=0 refused"
  awk '/nightly\]/ {n=1} n && /^enabled=0/ {print "enabled=1"; next} {print}' "$w/good.repo" > "$w/b3.repo"; mkrpm b3 "$w/pa.asc" "$w/b3.repo"; "$c" "$w/b3.rpm" "$fa" "$U" 2> /dev/null && bad "nightly enabled accepted" || ok "nightly enabled=1 refused"
  EXTRA=/etc/yum.repos.d/evil mkrpm b6 "$w/pa.asc" "$w/good.repo"; "$c" "$w/b6.rpm" "$fa" "$U" 2> /dev/null && bad "extra file in package accepted" || ok "package with an extra file refused"
  mkrpm b4 "$w/ab.asc" "$w/good.repo"; "$c" "$w/b4.rpm" "$fa" "$U" 2> /dev/null && bad "second primary key in package accepted" || ok "package with two primary keys refused"
  "$here/pubkey.sh" "$w/b.asc" "$fb" "$w/pb.asc"; mkrpm b5 "$w/pb.asc" "$w/good.repo"; "$c" "$w/b5.rpm" "$fa" "$U" 2> /dev/null && bad "foreign key in package accepted" || ok "package with a foreign key refused"
  # M1: a payload entry with an ABSOLUTE name (header list unchanged) must be refused and NOTHING may be written outside the temp dir. Uncompressed payload so the name can be patched in place.
  mkdir -p "$w/outside"; tgt=$w/outside/new-evil.sh; pad=/etc/pki/rpm-gpg/$(printf 'z%.0s' $(seq 1 $((${#tgt} + 20))))
  EXTRA=$pad UNC=1 mkrpm e1 "$w/pa.asc" "$w/good.repo"; old=".$pad"; new=$(printf '%*s' $(( ${#old} - ${#tgt} )) '' | tr ' ' '/')$tgt
  LC_ALL=C sed -i "s|$old|$new|" "$w/e1.rpm"
  lst=$(rpm2cpio "$w/e1.rpm" | cpio -t 2> /dev/null) || lst=""
  if grep -qF "$tgt" <<< "$lst"; then ok "escape package: payload really names $tgt (precondition)"
  elif ! rpm2cpio "$w/e1.rpm" > /dev/null 2>&1; then ok "escape package: this rpm2cpio rejects the patched payload itself (rpm >= 4.20; the check is exercised on ubuntu 24.04 = CI)"
  else bad "escape package not built as intended"; fi
  "$c" "$w/e1.rpm" "$fa" "$U" 2> /dev/null && bad "absolute payload name accepted" || ok "absolute payload name refused"
  [[ ! -e $tgt && -z $(ls -A "$w/outside") ]] && ok "nothing written outside the temp dir" || bad "a file was written to $tgt"
  # M2: a continuation line (second baseurl for dnf), "gpgcheck = 0" with spaces, a scriptlet
  awk '{print} /^baseurl=/ && !d {print "  https://evil.example/r"; d=1}' "$w/good.repo" > "$w/c1.repo"; mkrpm c1 "$w/pa.asc" "$w/c1.repo"; "$c" "$w/c1.rpm" "$fa" "$U" 2> /dev/null && bad "continuation line accepted" || ok "repo file continuation line refused"
  { cat "$w/good.repo"; printf 'gpgcheck = 0\n'; } > "$w/c2.repo"; mkrpm c2 "$w/pa.asc" "$w/c2.repo"; "$c" "$w/c2.rpm" "$fa" "$U" 2> /dev/null && bad "'gpgcheck = 0' accepted" || ok "repo file 'gpgcheck = 0' refused"
  POST=1 mkrpm c3 "$w/pa.asc" "$w/good.repo"; "$c" "$w/c3.rpm" "$fa" "$U" 2> /dev/null && bad "package with a %post scriptlet accepted" || ok "package with a scriptlet refused"
else echo "SKIPPED: rpmbuild/rpmsign missing"; [[ -z ${CI:-} ]] || bad "rpm tools missing in CI"; fi
exit $t
