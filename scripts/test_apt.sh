#!/usr/bin/env bash
# Self-test of build-apt.sh / sign-apt.sh / verify-apt.sh with THROWAWAY keys and test packages the test builds itself.
# Parts: (A) retention [bash only], (B) sign+verify+counter-checks on a hand-made tree [gpg, gpgv],
#        (C) the same on a tree built by apt-ftparchive [needs apt-ftparchive from apt-utils; otherwise SKIPPED with a notice].
# Never touches real keys or ~/.gnupg. Exit 0 = all run parts passed (skipped parts are listed, not guessed).
# shellcheck disable=SC2015  # `A && pass || fail` is the intended test idiom (pass never fails)
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
T=$(mktemp -d)
export GNUPGHOME=$T/gh1
G2=$T/gh2
cleanup() { for h in "$GNUPGHOME" "$G2"; do gpgconf --homedir "$h" --kill gpg-agent >/dev/null 2>&1 || true; done; rm -rf "$T"; }
trap cleanup EXIT
fails=0 skipped=()
pass() { echo "ok   $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
expect_fail() { local d=$1; shift; if "$@" > "$T/out" 2>&1; then fail "$d (verification passed but must fail)"; else pass "$d"; fi; }

command -v gpg > /dev/null && command -v gpgv > /dev/null || { echo "SKIPPED ALL: gpg/gpgv missing"; exit 0; }

# --- throwaway keys ---------------------------------------------------------------------------
genkey() { # home name passphrase
  mkdir -m 700 "$1"
  printf 'Key-Type: EDDSA\nKey-Curve: ed25519\nKey-Usage: sign\nName-Real: %s\nName-Email: t@example.org\nExpire-Date: 0\n%s\n%%commit\n' \
    "$2" "${3:+Passphrase: $3}" > "$1/spec"
  [[ -n $3 ]] || sed -i 's/^$/%no-protection/;' "$1/spec"
  GNUPGHOME=$1 gpg --batch --quiet --generate-key "$1/spec" 2> /dev/null
}
genkey "$GNUPGHOME" fs-test-1 secret-pass
genkey "$G2" fs-test-2 ""
FPR1=$(gpg --batch --list-keys --with-colons | awk -F: '/^fpr:/ {print $10; exit}')
FPR2=$(GNUPGHOME=$G2 gpg --batch --list-keys --with-colons | awk -F: '/^fpr:/ {print $10; exit}')
gpg --batch --export "$FPR1" > "$T/key1.pgp"
GNUPGHOME=$G2 gpg --batch --export "$FPR2" > "$T/key2.pgp"
printf 'secret-pass' > "$T/pass"; chmod 600 "$T/pass"

# --- test .deb files (dpkg-deb if present, otherwise ar: a .deb is ar(debian-binary, control.tar.gz, data.tar.gz)) ----
mkdeb() { # outdir name version arch
  local d=$T/mk.$2.$3
  mkdir -p "$d/pkg/DEBIAN" "$d/pkg/usr/share/$2" "$1"
  printf 'Package: %s\nVersion: %s\nArchitecture: %s\nMaintainer: FreeSynergy test <t@example.org>\nDescription: self-test package\n' "$2" "$3" "$4" > "$d/pkg/DEBIAN/control"
  echo "payload $3" > "$d/pkg/usr/share/$2/file"
  if command -v dpkg-deb > /dev/null; then
    dpkg-deb --build --root-owner-group "$d/pkg" "$1/$2_$3_$4.deb" > /dev/null
  else
    (cd "$d/pkg/DEBIAN" && tar --owner=0 --group=0 -czf "$d/control.tar.gz" ./control)
    (cd "$d/pkg" && tar --owner=0 --group=0 --exclude=./DEBIAN -czf "$d/data.tar.gz" .)
    echo '2.0' > "$d/debian-binary"
    (cd "$d" && ar rc "$1/$2_$3_$4.deb" debian-binary control.tar.gz data.tar.gz)
  fi
}

# --- A: retention -------------------------------------------------------------------------------
echo "== A retention (4 versions -> 3 stay, newest by version order, other package/suite untouched)"
for v in 1.0 1.2 1.10 1.1; do mkdeb "$T/debs-a" foo "$v" amd64; done
mkdeb "$T/debs-a" bar 0.1 amd64
"$here/build-apt.sh" --no-index "$T/debs-a" stable "$T/ra" > /dev/null
left=$(find "$T/ra/pool/stable" -name 'foo_*.deb' -printf '%f\n' | sort | paste -sd' ')
[[ $left == "foo_1.1_amd64.deb foo_1.10_amd64.deb foo_1.2_amd64.deb" || $left == "foo_1.10_amd64.deb foo_1.1_amd64.deb foo_1.2_amd64.deb" ]] && pass "retention keeps 1.1, 1.2, 1.10 and drops 1.0" || fail "retention left: $left"
[[ -f $T/ra/pool/stable/b/bar/bar_0.1_amd64.deb ]] && pass "other package untouched" || fail "bar vanished"
"$here/build-apt.sh" --no-index "$T/debs-a" testing "$T/ra" > /dev/null
[[ $(find "$T/ra/pool/testing" -name 'foo_*.deb' | wc -l) == 3 && $(find "$T/ra/pool/stable" -name 'foo_*.deb' | wc -l) == 3 ]] && pass "suites keep their own pool" || fail "suite pools"
mkdir "$T/bad2"; : > "$T/bad2/Foo_1.0_amd64.deb"
expect_fail "unusable package file name is refused" "$here/build-apt.sh" --no-index "$T/bad2" stable "$T/rb"
expect_fail "unknown suite is refused" "$here/build-apt.sh" --no-index "$T/debs-a" nightly "$T/rb"

# --- B/C: sign + verify + counter-checks on a tree ---------------------------------------------------
sign_verify() { # label repo
  local label=$1 repo=$2
  echo "== $label sign + verify"
  "$here/sign-apt.sh" --key "$FPR1" --passphrase-file "$T/pass" "$repo" stable > "$T/out" 2>&1 && pass "$label: signing ran" || { fail "$label: signing failed: $(cat "$T/out")"; return; }
  grep -q -e 'secret-pass' -e 'PRIVATE KEY' "$T/out" && fail "$label: sign output leaks secrets" || pass "$label: sign output shows no key material"
  head -1 "$repo/dists/stable/InRelease" | grep -q 'BEGIN PGP SIGNED MESSAGE' && grep -q 'BEGIN PGP SIGNATURE' "$repo/dists/stable/Release.gpg" && pass "$label: InRelease clear-signed, Release.gpg detached" || fail "$label: wrong signature files"
  "$here/verify-apt.sh" --fingerprint "$FPR1" "$repo" stable "$T/key1.pgp" > "$T/out" 2>&1 && pass "$label: verification OK" || fail "$label: verification failed: $(cat "$T/out")"
  expect_fail "$label: wrong key (key of another throwaway identity) fails" "$here/verify-apt.sh" "$repo" stable "$T/key2.pgp"
  expect_fail "$label: right key but wrong expected fingerprint fails" "$here/verify-apt.sh" --fingerprint "$FPR2" "$repo" stable "$T/key1.pgp"
  local c
  c=$T/c1; rm -rf "$c"; cp -a "$repo" "$c"
  f=$(find "$c/pool" -name '*.deb' | head -1); printf 'X' | dd of="$f" bs=1 seek=10 conv=notrunc 2> /dev/null
  expect_fail "$label: manipulated package (same size) fails" "$here/verify-apt.sh" "$c" stable "$T/key1.pgp"
  c=$T/c2; rm -rf "$c"; cp -a "$repo" "$c"
  f=$(find "$c/pool" -name '*.deb' | head -1); echo more >> "$f"
  expect_fail "$label: manipulated package (size changed) fails" "$here/verify-apt.sh" "$c" stable "$T/key1.pgp"
  c=$T/c3; rm -rf "$c"; cp -a "$repo" "$c"
  sed -i 's/^Label: FreeSynergy/Label: Evil/' "$c/dists/stable/Release"
  expect_fail "$label: manipulated Release fails" "$here/verify-apt.sh" "$c" stable "$T/key1.pgp"
  c=$T/c4; rm -rf "$c"; cp -a "$repo" "$c"
  sed -i '0,/^Version: /s//Version: 9/' "$c/dists/stable/main/binary-amd64/Packages"
  expect_fail "$label: manipulated Packages (hash in Release no longer matches) fails" "$here/verify-apt.sh" "$c" stable "$T/key1.pgp"
  c=$T/c5; rm -rf "$c"; cp -a "$repo" "$c"
  sed -i 's/^Label: FreeSynergy/Label: Evil/' "$c/dists/stable/InRelease"
  expect_fail "$label: manipulated InRelease fails" "$here/verify-apt.sh" "$c" stable "$T/key1.pgp"
  c=$T/c7; rm -rf "$c"; cp -a "$repo" "$c"
  h=$(find "$c/dists" -path '*/by-hash/SHA256/*' -type f | head -1)
  if [[ -n $h ]]; then
    printf 'X' | dd of="$h" bs=1 seek=5 conv=notrunc 2> /dev/null
    expect_fail "$label: manipulated by-hash copy fails" "$here/verify-apt.sh" "$c" stable "$T/key1.pgp"
    c=$T/c8; rm -rf "$c"; cp -a "$repo" "$c"; rm "$(find "$c/dists" -path '*/by-hash/SHA256/*' -type f | head -1)"
    expect_fail "$label: missing by-hash copy fails" "$here/verify-apt.sh" "$c" stable "$T/key1.pgp"
  else
    fail "$label: tree has no by-hash directory"
  fi
  c=$T/c6; rm -rf "$c"; cp -a "$repo" "$c"; rm "$c/dists/stable/Release.gpg"
  expect_fail "$label: missing Release.gpg fails" "$here/verify-apt.sh" "$c" stable "$T/key1.pgp"
  [[ -z $(find "$repo" -name '*.pgp' -o -name '*secret*') ]] && pass "$label: no key files in the tree" || fail "$label: key file in the tree"
}

# B: hand-made tree (a fake .deb is enough: indexes only hash the files)
mk_synth() { # repo
  local r=$1 b=$1/dists/stable/main/binary-amd64 f
  mkdir -p "$r/pool/stable/f/foo" "$b"
  f=$r/pool/stable/f/foo/foo_1.0_amd64.deb; head -c 3000 /dev/urandom > "$f"
  printf 'Package: foo\nVersion: 1.0\nArchitecture: amd64\nFilename: pool/stable/f/foo/foo_1.0_amd64.deb\nSize: %s\nSHA256: %s\n\n' \
    "$(stat -c %s "$f")" "$(sha256sum "$f" | cut -d' ' -f1)" > "$b/Packages"
  gzip -9 -n -c "$b/Packages" > "$b/Packages.gz"; xz -c "$b/Packages" > "$b/Packages.xz"
  mkdir -p "$b/by-hash/SHA256"
  for n in Packages Packages.gz Packages.xz; do cp "$b/$n" "$b/by-hash/SHA256/$(sha256sum "$b/$n" | cut -d' ' -f1)"; done
  { printf 'Origin: FreeSynergy\nLabel: FreeSynergy\nSuite: stable\nCodename: stable\nDate: Sat, 14 Nov 2026 00:00:00 UTC\nArchitectures: amd64\nComponents: main\nAcquire-By-Hash: yes\nSHA256:\n'
    for n in Packages Packages.gz Packages.xz; do printf ' %s %s main/binary-amd64/%s\n' "$(sha256sum "$b/$n" | cut -d' ' -f1)" "$(stat -c %s "$b/$n")" "$n"; done; } > "$r/dists/stable/Release"
}
mk_synth "$T/synth"
sign_verify "B(hand-made tree)" "$T/synth"

# C: tree built by apt-ftparchive
if command -v apt-ftparchive > /dev/null; then
  mkdeb "$T/debs-c" foo 1.0 amd64; mkdeb "$T/debs-c" foo 1.1 amd64; mkdeb "$T/debs-c" libbar 2.0 amd64
  "$here/build-apt.sh" "$T/debs-c" stable "$T/built" > "$T/out" 2>&1 && pass "C: apt-ftparchive build ran" || fail "C: build failed: $(cat "$T/out")"
  [[ -s $T/built/dists/stable/Release && -s $T/built/dists/stable/main/binary-amd64/Packages.xz ]] && pass "C: Release and Packages.xz exist" || fail "C: index files missing"
  sign_verify "C(apt-ftparchive tree)" "$T/built"
  grep -q '^Acquire-By-Hash: yes' "$T/built/dists/stable/Release" && pass "C: Release says Acquire-By-Hash: yes" || fail "C: Acquire-By-Hash missing"
  grep -q '^Valid-Until:' "$T/built/dists/stable/Release" && fail "C: Valid-Until present without --valid-days" || pass "C: no Valid-Until by default"
  "$here/build-apt.sh" --valid-days 2 "$T/debs-c" stable "$T/built2" > /dev/null
  vu=$(sed -n 's/^Valid-Until: //p' "$T/built2/dists/stable/Release"); dt=$(sed -n 's/^Date: //p' "$T/built2/dists/stable/Release")
  [[ -n $vu && $(( $(date -u -d "$vu" +%s) - $(date -u -d "$dt" +%s) )) == 172800 ]] && pass "C: --valid-days 2 gives Valid-Until = Date + 2 days" || fail "C: Valid-Until wrong: '$vu' vs '$dt'"
  find "$T/built" \( -type l -o -type f -links +1 \) | grep -q . && fail "C: tree contains symlinks/hardlinks (Pages rejects them)" || pass "C: no symlinks/hardlinks in the tree"
else
  skipped+=("C: apt-ftparchive not installed (package apt-utils); the apt-ftparchive build path is NOT tested here")
  echo "SKIP C: apt-ftparchive not installed (package apt-utils)"
fi

# D: make-site publishes only the wanted key
echo "== D make-site key filter"
gpg --batch --armor --export "$FPR1" > "$T/k1.asc"; GNUPGHOME=$G2 gpg --batch --armor --export "$FPR2" > "$T/k2.asc"; cat "$T/k1.asc" "$T/k2.asc" > "$T/k12.asc"
"$here/make-site.sh" "$T/synth" "$T/site" "$T/k1.asc" https://example.org/apt/ "$FPR1" > "$T/out" 2>&1 && pass "D: single wanted key accepted" || fail "D: rejected: $(cat "$T/out")"
n=$(gpg --batch --show-keys --with-colons "$T/site/apt/freesynergy-archive-keyring.pgp" 2> /dev/null | grep -c '^pub:')
[[ $n == 1 ]] && pass "D: published keyring has exactly one primary key" || fail "D: keyring has $n primary keys"
grep -q '^Suites: stable' "$T/site/apt/freesynergy.sources" && pass "D: sources file points at stable" || fail "D: sources suite"
expect_fail "D: key file with a second primary key is refused" "$here/make-site.sh" "$T/synth" "$T/site2" "$T/k12.asc" https://example.org/apt/ "$FPR1"
expect_fail "D: key file with another key than wanted is refused" "$here/make-site.sh" "$T/synth" "$T/site3" "$T/k2.asc" https://example.org/apt/ "$FPR1"
[[ ! -e $T/site2/apt/freesynergy-archive-keyring.pgp ]] && pass "D: refused run published nothing" || fail "D: key published despite refusal"

echo
for s in "${skipped[@]}"; do echo "SKIPPED $s"; done
[[ $fails == 0 ]] || { echo "$fails test(s) failed"; exit 1; }
echo "all run tests passed${skipped:+ (with skipped parts)}"
