#!/usr/bin/env bash
# Gate for createrepo_rs: build the metadata of RPMDIR with both tools, compare the package list (name, version, checksum, location).
# Prints the tool to use on stdout: createrepo_rs when identical, otherwise createrepo_c (fallback); details on stderr.
# Usage: gate-createrepo.sh RPMDIR     (needs createrepo_rs, createrepo_c, xmllint)
set -euo pipefail
src=${1:?usage: gate-createrepo.sh RPMDIR}; t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
list() { # dir -> sorted "name version checksum location" lines of primary.xml
  local f; f=$(ls "$1"/repodata/*primary.xml*); { case $f in *.gz) zcat "$f" ;; *.zst) zstdcat "$f" ;; *.xz) xzcat "$f" ;; *) cat "$f" ;; esac; } |
    xmllint --xpath '//*[local-name()="package"]' - | tr '\n' ' ' | sed 's/<\/package>/\n/g' |
    sed -E 's/.*<name>([^<]*)<\/name>.*<version epoch="[0-9]*" ver="([^"]*)" rel="([^"]*)".*<checksum[^>]*>([^<]*)<.*<location href="([^"]*)".*/\1 \2 \3 \4 \5/' | sort
}
for tool in createrepo_rs createrepo_c; do mkdir "$t/$tool"; cp "$src"/*.rpm "$t/$tool/"; "$tool" "$t/$tool" > /dev/null; list "$t/$tool" > "$t/$tool.txt"; done
if [[ -s $t/createrepo_c.txt ]] && diff -u "$t/createrepo_c.txt" "$t/createrepo_rs.txt" >&2; then echo createrepo_rs; else echo "note: differs, fallback createrepo_c" >&2; echo createrepo_c; fi
