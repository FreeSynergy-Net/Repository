#!/usr/bin/env bash
# Run test_rpm.sh (and rpmlint on the given rpms) in a throwaway Fedora container. Local use only; never on a server.
# Usage: test-rpm-container.sh RPMDIR [IMAGE]   (CREATEREPO=createrepo_rs only if that binary is in the image)
set -euo pipefail
rpms=$(cd "${1:?usage: test-rpm-container.sh RPMDIR [IMAGE]}" && pwd); image=${2:-registry.fedoraproject.org/fedora:45}
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
podman run --rm -e CREATEREPO="${CREATEREPO:-createrepo_c}" -v "$root:/src:ro,z" -v "$rpms:/rpms:ro,z" "$image" bash -c '
  dnf -y -q install createrepo_c rpm-build rpm-sign gnupg2 rpmlint sed > /dev/null 2>&1
  cp -r /src /w && cd /w && bash scripts/test_rpm.sh /rpms
  echo "--- NAMED FINDING unowned-directory (open until fs-starter owns them via %dir, order 5; must then be empty)"
  for f in /rpms/*.rpm; do rpm -qpl "$f" | sort -u > /tmp/l; while read -r p; do d=$(dirname "$p"); while [ "$d" != / ]; do grep -qx "$d" /tmp/l || case $d in /usr/share/freesynergy*|/usr/libexec/freesynergy*) echo "UNOWNED $(basename "$f"): $d" ;; esac; d=$(dirname "$d"); done; done < /tmp/l; done | sort -u
  echo "--- rpmlint (known finding: directories owned by no package until fs-starter owns them, order 5)"; rpmlint /rpms/*.rpm || true
'
