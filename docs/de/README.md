# Repository (Deutsch)

Signierte Paketquellen von FreeSynergy (jetzt APT, später RPM). Die Releases der Programm-Repos bleiben die Quelle der Wahrheit (`.deb` + `.asc`);
dieses Repo baut daraus nur eine abgeleitete, signierte Sicht. Nichts wird hier von selbst veröffentlicht.

## Aufbau (zuerst GitHub Pages, `https://freesynergy-net.github.io/Repository/`)

```
index.html                                  Fingerabdruck + Links
apt/freesynergy.sources                     fertige deb822-Datei
apt/freesynergy-archive-keyring.{pgp,asc}   öffentlicher Schlüssel (binär für Signed-By, ASCII für Menschen)
apt/dists/<suite>/{Release,InRelease,Release.gpg}
rpm/RPM-GPG-KEY-freesynergy                 öffentlicher Schlüssel (derselbe wie bei apt)
rpm/stable/{*.rpm,repodata/}                der EINE dnf-Kanal = alle Releases mit Versions-Tag, auch Vorabversionen (nie ein ungetaggter Bau); repodata/repomd.xml.asc = abgetrennte Signatur (repo_gpgcheck=1)
apt/dists/<suite>/main/binary-amd64/Packages{,.gz,.xz}
apt/pool/<suite>/<prefix>/<paket>/<paket>_<version>_<arch>.deb
```

Suiten: `stable` (= Releases), `testing` (= Vorab-Releases). Architekturen `amd64` und `arm64` indexiert. Aufbewahrung: 3 Versionen je Paket, Architektur und Suite.
Ein späterer Spiegel (Codeberg Pages, eigene Domain) ist derselbe Baum; Vertrauen steckt in der Signatur, nicht im Ort (ADR 0062).

## Ablauf

1. `fetch-releases.sh`: `.deb` aus den Releases der genannten Repos, nur mit gültiger Signatur des Projektschlüssels.
2. `build-apt.sh`: `apt-ftparchive` (zustandslos, die Seite wird jedes Mal komplett aus den Releases neu gebaut).
3. Signatur nur im getrennten Job `sign` (`GPG_PRIVATE_KEY`, `GPG_PASSPHRASE`, `scripts/sign-apt.sh`, temporäres GNUPGHOME; die fs-release-Aktion `sign-apt` ist nicht gemergt und wird nicht benutzt).
4. `verify-apt.sh` gegen den öffentlichen Schlüssel aus fs-release, dann `make-site.sh`, dann (noch nicht ausgeführt) Pages-Deploy.

## Signier-Umgebung (Owner, einmalig; existiert noch nicht)

1. Settings > Environments > neue Umgebung `apt-signing`: Deployment-Branch nur `main`, Freigabe durch den Owner.
2. Secrets **nur in dieser Umgebung** (nicht im Repo, nicht in der Organisation): `GPG_PRIVATE_KEY` = Export **nur des Signier-Unterschlüssels**
   (`gpg --armor --export-secret-subkeys <Unterschlüssel-Fpr>!`; der Hauptschlüssel bleibt offline), `GPG_PASSPHRASE`.
3. Settings > Actions > General: „Require actions to be pinned to a full-length commit SHA“ einschalten.
4. Settings > Pages: Quelle = GitHub Actions. Dann `publish` starten (Eingaben: `repos`, `key_ref` = geprüfter fs-release-Commit, `deploy`).

## Neu signieren und `Valid-Until`

Standardmäßig hat `Release` kein `Valid-Until`, das Repo läuft für Clients nie ab. `build-apt.sh --valid-days N` setzt `Valid-Until = Date + N Tage`
(`APT::FTPArchive::Release::ValidTime`); dann MUSS planmäßig neu gebaut und signiert werden, sonst lehnen Clients das Repo ab. Entscheidung der Strategie offen.

## Grenzen (nicht belegt)

- `publish.yml` und Pages-Deploy sind nie gelaufen; alle Aktionen sind per voller SHA gepinnt (`upload-pages-artifact` v5.0.0, `deploy-pages` v5.0.1, am 23.11.2026 gegen die Tags geprüft); `key_ref` ist ein geprüfter fs-release-Commit.
- `fetch-releases.sh` und `make-site.sh` liefen nicht gegen echte Releases (Trockenlauf mit lokalen Testbauten zentinel 26.11.2-1, kanidmd 1.12.1-1).
- Der Schlüssel im Secret ist angenommen als nur Unterschlüssel; er läuft 2027-11-07 ab (vorher verlängern, Keyring neu veröffentlichen).
- Selbsttest und Trockenlauf (`scripts/test-container.sh`) in debian:13, debian:12, ubuntu:24.04: apt update/install, manipulierter Index/InRelease abgelehnt.

## rpm-Kanal

`freesynergy-release` (gebaut mit `fs-blueprint package release --fingerprint <festgelegter FPR> --pages-url https://freesynergy-net.github.io/Repository`) zeigt dnf auf `<pages>/rpm/stable` (EINE Sektion `[freesynergy]`, `name=FreeSynergy`, aktiv), mit `gpgcheck=1` und `repo_gpgcheck=1`.

Erstinstallation immer in dieser Reihenfolge: `<pages>/rpm/RPM-GPG-KEY-freesynergy` holen, Fingerabdruck vergleichen (`16A4 A3EE 563A EF51 FCF0 C55D ED7B 57C4 A190 4342`), `rpm --import`, dann `dnf install --setopt=localpkg_gpgcheck=1 <pages>/rpm/freesynergy-release.noarch.rpm` (Fedora prüft die Signatur lokaler/URL-Pakete sonst nicht, ein fehlender Schlüsselimport fiele nicht auf). Die Version von `freesynergy-release` folgt der fs-blueprint-Version; bei Schlüssel- oder URL-Wechsel MUSS `--pkg-version` im Job `release-pkg` von `publish.yml` erhöht werden.
Die Reihenfolge ist wichtig, weil das Signieren eines Pakets dessen Prüfsumme ändert: `fetch-releases.sh` (`FETCH_EXT=rpm`) -> `sign-rpm.sh ... packages DIR` (rpmsign, Schlüssel-Job) ->
`build-rpm.sh RPMDIR stable OUTDIR` (repodata mit `createrepo_c` aus dem Ubuntu-Archiv, im Schlüssel-Job) -> `sign-rpm.sh ... repo rpm/<kanal>` (`repomd.xml.asc`).
`gate-createrepo.sh` (Job `rpm-index-gate`, OHNE Schlüssel): createrepo_rs 0.1.9 (GPL-2.0, nur CI, nie ausgeliefert) baut den Index aus den signierten Paketen neu und muss dem Index des Schlüssel-Jobs gleichen; ein Unterschied macht den Lauf rot, nichts wird veröffentlicht (kein Rückfall).

Eine Freigabe je Lauf: publish.yml hat genau EINEN Job mit dem Schlüssel, `sign` (Environment `apt-signing`): rpm-Pakete, Index, repomd.xml und die apt-Suiten werden dort signiert. `scripts/check-key-jobs.sh` (check.yml, mit 5 Mutanten in `test_check_key_jobs.sh`) hält diese Form: genau ein Job mit `secrets.GPG_`, in `apt-signing`, kein `cargo install`, kein fremdes `uses:`, das Gate in `deploy.needs`. Bedrohungsmodell (ehrlich): schützt vor VERSEHEN, nicht vor jemandem, der Workflow/Toolchain/Skripte ändern kann. Noch nicht live gezeigt: der erste echte Lauf (eine Freigabe, Gate grün); `scripts/test_fetch.sh` (Rot-Test: getaggte Releases und Vorabversionen kommen hinein, das ungetaggte `nightly` nie) nutzt ein vorgetäuschtes `gh`, kein Netz.
Lokales Gate (podman, Wegwerf-Fedora-Container, Wegwerf-Schlüssel nur darin): `scripts/test-rpm-container.sh RPMDIR`. Es prüft: Installation klappt; manipuliertes Paket, manipuliertes repomd.xml und unsigniertes Paket werden aus dem richtigen Grund abgelehnt;
Verzeichniseigentum je Paket samt Requires-Kette (`unowned-dirs.sh`, Befund UNOWNED bleibt benannt sichtbar); rpmlint (jedes E = rot, W erlaubt).


### Nightly (Testbauten ohne Tag)

`nightly.yml` (Entwurf, von einer Person per `workflow_dispatch` gestartet: `repo`, `ref` = `main` oder eine volle Commit-SHA, die Vorfahr von origin/main ist (Branches und Tags werden im ersten Job vor Bau und Signatur abgelehnt; `scripts/nightly-check-ref.sh`, Test `scripts/test_nightly_ref.sh`), `package`, `bins`, `key_ref`) baut EIN Repository in der CI (ohne Secrets). Der Job `sign` prüft vor dem ersten Secret nochmals, dass der gebaute Commit (jeder Bau schreibt ihn auf) dem geprüften entspricht (`scripts/nightly-verify-built.sh`). Signiert wird in der Umgebung `apt-signing` (dieselben Secrets, nichts Neues). Danach liegen die rpm-Dateien samt `.rpm.asc` im rollenden Vorab-Release `nightly` dieses Repositorys (3 Versionen je Paket und Architektur, `scripts/nightly-retain.sh`).
Version: `<nächste>~nightly.<UTC-Zeit>.g<sha7>` (`scripts/nightly-version.sh`; sortiert nach der letzten und vor der nächsten Release). `publish.yml` nimmt es NICHT auf (nur Releases mit Versions-Tag kommen in den einen Kanal `rpm/stable`): es ist ein Download für Tester. Nie geht etwas lokal Gebautes hinein.
Die Prüfung des Schlüssels nutzt `scripts/pubkey.sh` (genau ein Primärschlüssel, der festgelegte Fingerabdruck), die Signaturprüfung `scripts/check-rpm-signed.sh` (`rpm -K` allein meldet für ein UNSIGNIERTES Paket Erfolg; verlangt wird der Text `digests signatures OK`). Vor dem Signieren von `freesynergy-release` läuft `scripts/check-release-pkg.sh` (eigener Job `release-check` OHNE Environment und Secrets; das Paket wird nie entpackt: der Payload wird aufgelistet und muss genau Schlüsseldatei und Repo-Datei als reguläre Dateien enthalten, dann wird jede nach stdout gelesen; beide Dateien exakt root:root, 0644 mit den erwarteten Flags (Repo-Datei `%config(noreplace)`); keine Scriptlets, Trigger, Obsoletes oder Conflicts, soweit der prüfende rpm sie kennt: `release-check` läuft in einem per Digest festgelegten Fedora-45-Container (rpm 6.1, kennt auch `%preuntrans`/`%postuntrans`); das Skript lehnt einen rpm ohne diese Tags ab; keine Abhängigkeiten außer `rpmlib()` und den eigenen `config()`/Namens-Provides; der Schlüssel ist der festgelegte Primärschlüssel; die Repo-Datei hat eine strenge Zeilenform (keine Fortsetzungszeilen, keine Leerzeichen um `=`) und genau die erwarteten `baseurl`, `enabled`, `gpgcheck`, `repo_gpgcheck`, `gpgkey`). Der Schlüssel-Job `rpm-packages` vergleicht nur die sha256 des Pakets mit der von `release-check` freigegebenen.

## GitHub Pages einschalten (Eigentümer, einmalig; nicht durch Agenten)

Repository `FreeSynergy-Net/Repository` > Settings > Pages > Build and deployment > Source: **GitHub Actions**. Dann den Workflow `publish` starten (Actions > publish > Run workflow, `deploy` anhaken).
