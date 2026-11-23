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
exit $t
