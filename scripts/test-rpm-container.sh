#!/usr/bin/env bash
# Run test_rpm.sh (and rpmlint on the given rpms) in a throwaway Fedora container. Local use only; never on a server.
# Usage: test-rpm-container.sh RPMDIR [IMAGE]   (CREATEREPO=createrepo_rs only if that binary is in the image)
set -euo pipefail
rpms=$(cd "${1:?usage: test-rpm-container.sh RPMDIR [IMAGE]}" && pwd); image=${2:-registry.fedoraproject.org/fedora:45}
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
podman run --rm -e CREATEREPO="${CREATEREPO:-createrepo_c}" -v "$root:/src:ro,z" -v "$rpms:/rpms:ro,z" "$image" bash -c '
  dnf -y -q install createrepo_c rpm-build rpm-sign gnupg2 rpmlint sed > /dev/null 2>&1
  cp -r /src /w && cd /w; t=0; bash scripts/test_rpm.sh /rpms || t=1
  echo "--- NAMED FINDING unowned-directory (per package: itself + its Requires chain; open until fs-starter owns them via %dir, PKG-5; must then be empty)"
  bash scripts/unowned-dirs.sh /rpms
  echo "--- rpmlint: any E makes the gate red (exit code of rpmlint); W alone do not (see docs)"; rpmlint /rpms/*.rpm; r=$?; exit $((r | t))
'
