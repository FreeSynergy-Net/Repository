#!/usr/bin/env bash
# Red test of fetch-releases.sh with a fake `gh` (no network): ONE channel takes tagged releases AND tagged pre-releases, but
# shellcheck disable=SC2012,SC2015
# NEVER an untagged build (the rolling pre-release `nightly`), and never a package whose signature is not the project key.
# Counter-check: delete the tag filter line in fetch-releases.sh and this test must go red ("nightly" taken).
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd); w=$(mktemp -d); trap 'gpgconf --homedir "$w/g" --kill gpg-agent > /dev/null 2>&1; rm -rf "$w"' EXIT
fail=0; ok() { echo "PASS: $1"; }; bad() { echo "FAIL: $1"; fail=1; }
mkdir -m700 "$w/g" "$w/bin"; export GNUPGHOME=$w/g
gpg --batch -q --passphrase '' --quick-gen-key "T <t@example.invalid>" rsa3072 sign never 2> /dev/null
fpr=$(gpg --list-keys --with-colons | awk -F: '/^fpr:/ {print $10; exit}'); gpg --batch --armor --export "$fpr" > "$w/key.asc"
# fake gh: `release list` prints every tag (the script filters), `release download` writes a package + detached signature (the tag "evil" is signed by nobody)
cat > "$w/bin/gh" <<'F'
#!/usr/bin/env bash
if [[ $2 == list ]]; then printf '%s\n' v26.11_3 nightly v0.0.4 latest evil; exit 0; fi
tag=$3; while [[ $1 != -D ]]; do shift; done; d=$2; f=$d/fs-demo-$tag-1.noarch.rpm; echo "$tag" > "$f"
[[ $tag == evil ]] && printf 'junk' > "$f.asc" || gpg --batch --armor --detach-sign -o "$f.asc" "$f"
F
chmod +x "$w/bin/gh"
PATH=$w/bin:$PATH FETCH_EXT=rpm "$here/fetch-releases.sh" all "$w/out" "$w/key.asc" "$fpr" fs-demo > /dev/null 2>&1
got=$(ls "$w/out" 2> /dev/null | sort | paste -sd' ')
[[ $got == "fs-demo-v0.0.4-1.noarch.rpm fs-demo-v26.11_3-1.noarch.rpm" ]] && ok "tagged releases taken; untagged (nightly, latest) and badly signed refused: $got" || bad "wrong set taken: $got"
[[ $got == *nightly* ]] && bad "the untagged build nightly went into the channel"
exit "$fail"
