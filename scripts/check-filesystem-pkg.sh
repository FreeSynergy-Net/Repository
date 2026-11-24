#!/usr/bin/env bash
# Check of freesynergy-filesystem BEFORE it is signed (built in a job without secrets). Usage: check-filesystem-pkg.sh RPM
# The package may own exactly the six shared folders and nothing else: no file, no scriptlet/trigger/obsoletes/conflicts, no dependency except
# rpmlib() and its own name; every folder root:root 0755; payload = the same six directories (listed, NEVER unpacked); and the gate
# unowned-dirs.sh over this package must print nothing (every folder it lists has an owner). Same trust rule as check-release-pkg.sh.
set -euo pipefail
rpm=$(readlink -f "${1:?usage: check-filesystem-pkg.sh RPM}"); here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
die() { echo "error: $rpm: $*" >&2; exit 1; }; q() { rpm -qp "$@" "$rpm" 2> /dev/null; }
D=$(printf '%s\n' /usr/libexec/freesynergy /usr/libexec/freesynergy/modules /usr/share/freesynergy /usr/share/freesynergy/frontends /usr/share/freesynergy/modules /usr/share/freesynergy/programs)
n=$(q --qf '%{NAME}'); v=$(q --qf '%{VERSION}-%{RELEASE}')
[[ $n == freesynergy-filesystem && $(q --qf '%{ARCH}') == noarch ]] || die "not the noarch package freesynergy-filesystem"
[[ -z $(q --scripts --triggers --filetriggers --obsoletes --conflicts) ]] || die "scriptlets, triggers, obsoletes or conflicts"
[[ -z $(q --recommends --suggests --supplements --enhances) ]] || die "Recommends/Suggests/Supplements/Enhances"
[[ -z $(q --requires | grep -vE '^rpmlib\([A-Za-z0-9]+\) <= [0-9.:~^-]+$' || true) ]] || die "unexpected Requires"
[[ $(q --provides) == "$n = $v" ]] || die "unexpected Provides"
[[ $(q -l | sort) == "$D" ]] || die "file list is not exactly the six shared folders"
[[ $(q --qf '[%{FILEMODES:perms} %{FILEUSERNAME} %{FILEGROUPNAME}\n]' | sort -u) == "drwxr-xr-x root root" ]] || die "a folder is not drwxr-xr-x root:root"
[[ $(rpm2cpio "$rpm" | cpio -tv --quiet 2> /dev/null | cut -c1 | sort -u) == d && $(rpm2cpio "$rpm" | cpio -t --quiet 2> /dev/null | sed 's|^\.||' | sort) == "$D" ]] || die "payload is not exactly the six folders"
cp "$rpm" "$w/"; u=$("$here/unowned-dirs.sh" "$w") || die "unowned-dirs.sh failed"; [[ -z $u ]] || die "folder without owner: $u"
echo "ok: $rpm owns exactly the six shared folders, nothing unowned"
