#!/usr/bin/env bash
# Counter-test of check-key-jobs.sh: the real files pass; each mutant of publish.yml must turn the check red.
# shellcheck disable=SC2015,SC2016
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd); wf=$here/../.github/workflows; w=$(mktemp -d); trap 'rm -rf "$w"' EXIT; fail=0
ok() { echo "PASS: $1"; }; bad() { echo "FAIL: $1"; fail=1; }
c=$here/check-key-jobs.sh
"$c" "$wf/publish.yml" rpm-index-gate > /dev/null && ok "publish.yml passes" || bad "publish.yml refused"
"$c" "$wf/nightly.yml" > /dev/null && ok "nightly.yml passes" || bad "nightly.yml refused"
mutant() { # NAME  (the mutated file is $w/m.yml, made from stdin-filter in $2..)
  local name=$1; shift; "$@" < "$wf/publish.yml" > "$w/m.yml"; cmp -s "$w/m.yml" "$wf/publish.yml" && { bad "mutant $name changed nothing"; return; }
  "$c" "$w/m.yml" rpm-index-gate > /dev/null 2>&1 && bad "mutant accepted: $name" || ok "mutant refused: $name"
}
mutant "environment removed from the key job" sed '/^    environment: apt-signing$/d'
mutant "second job with a secret" sed '/^  rpm-index-gate:$/i\  evil:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: echo "$K"\n        env:\n          K: ${{ secrets.GPG_PRIVATE_KEY }}'
mutant "createrepo_rs (cargo install) inside the key job" sed 's/rpm gnupg createrepo-c xz-utils$/rpm gnupg createrepo-c xz-utils \&\& cargo install createrepo_rs/'
mutant "gate missing in deploy.needs" sed 's/needs: \[sign, rpm-index-gate\]/needs: sign/'
mutant "foreign action inside the key job" sed '0,/^      - name: Tools from the Ubuntu archive$/s//      - uses: someone\/else@v1\n      - name: Tools from the Ubuntu archive/'
exit "$fail"
