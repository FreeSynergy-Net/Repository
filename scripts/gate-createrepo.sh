#!/usr/bin/env bash
# Gate for the index: createrepo_rs (third-party Rust code, runs in a job WITHOUT the key) rebuilds the metadata from the SIGNED packages
# and the package list (name, version, checksum, location) must equal the one of the key job (createrepo_c). A difference is an error: nothing is published.
# Usage: gate-createrepo.sh PUBLISHED_CHANNEL_DIR     (the dir with *.rpm and repodata/ made by the key job; needs createrepo_rs, xmllint)
set -euo pipefail
ref=${1:?usage: gate-createrepo.sh PUBLISHED_CHANNEL_DIR}; t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
list() { # dir -> sorted "name version checksum location" lines of primary.xml
  local f; f=$(ls "$1"/repodata/*primary.xml*); { case $f in *.gz) zcat "$f" ;; *.zst) zstdcat "$f" ;; *.xz) xzcat "$f" ;; *) cat "$f" ;; esac; } |
    xmllint --xpath '//*[local-name()="package"]' - | tr '\n' ' ' | sed 's/<\/package>/\n/g' |
    sed -E 's/.*<name>([^<]*)<\/name>.*<version epoch="[0-9]*" ver="([^"]*)" rel="([^"]*)".*<checksum[^>]*>([^<]*)<.*<location href="([^"]*)".*/\1 \2 \3 \4 \5/' | sort
}
compgen -G "$ref/*.rpm" > /dev/null || { echo "error: no .rpm in $ref" >&2; exit 1; }
mkdir "$t/rs"; cp "$ref"/*.rpm "$t/rs/"; createrepo_rs "$t/rs" > /dev/null
list "$ref" > "$t/ref.txt"; list "$t/rs" > "$t/rs.txt"
[[ -s $t/ref.txt ]] || { echo "error: the index of the key job lists no package" >&2; exit 1; }
diff -u "$t/ref.txt" "$t/rs.txt" >&2 || { echo "error: createrepo_rs and createrepo_c disagree - nothing is published" >&2; exit 1; }
echo "index gate: createrepo_rs equals the index of the key job ($(wc -l < "$t/ref.txt") packages)"
