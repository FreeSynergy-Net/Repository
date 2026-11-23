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
rpm/stable/{*.rpm,repodata/}                dnf-Kanal = Releases; repodata/repomd.xml.asc = abgetrennte Signatur (repo_gpgcheck=1)
rpm/nightly/{*.rpm,repodata/}               dnf-Kanal = Vorabversionen
apt/dists/<suite>/main/binary-amd64/Packages{,.gz,.xz}
apt/pool/<suite>/<prefix>/<paket>/<paket>_<version>_<arch>.deb
```

Suiten: `stable` (= Releases), `testing` (= Vorab-Releases). Architekturen `amd64` und `arm64` indexiert. Aufbewahrung: 3 Versionen je Paket, Architektur und Suite.
Ein späterer Spiegel (Codeberg Pages, eigene Domain) ist derselbe Baum; Vertrauen steckt in der Signatur, nicht im Ort (ADR 0062).

## Ablauf

1. `fetch-releases.sh`: `.deb` aus den Releases der genannten Repos, nur mit gültiger Signatur des Projektschlüssels.
2. `build-apt.sh`: `apt-ftparchive` (zustandslos, die Seite wird jedes Mal komplett aus den Releases neu gebaut).
3. Signatur nur im getrennten Job `sign` (`GPG_PRIVATE_KEY`, `GPG_PASSPHRASE`, fs-release-Aktion `sign-apt`, temporäres GNUPGHOME).
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

- `publish.yml` und Pages-Deploy sind nie gelaufen; drei `REPLACE_SHA` (fs-release `sign-apt` nach dem 0.0.7-Merge, `upload-pages-artifact`, `deploy-pages`) werden nach Prüfung eingetragen.
- `fetch-releases.sh` und `make-site.sh` liefen nicht gegen echte Releases (Trockenlauf mit lokalen Testbauten zentinel 26.11.2-1, kanidmd 1.12.1-1).
- Der Schlüssel im Secret ist angenommen als nur Unterschlüssel; er läuft 2027-11-07 ab (vorher verlängern, Keyring neu veröffentlichen).
- Selbsttest und Trockenlauf (`scripts/test-container.sh`) in debian:13, debian:12, ubuntu:24.04: apt update/install, manipulierter Index/InRelease abgelehnt.

## rpm-Kanal

`freesynergy-release` (gebaut mit `fs-blueprint package release --pages-url https://freesynergy-net.github.io/Repository`) zeigt dnf auf `<pages>/rpm/stable` (aktiv) und `<pages>/rpm/nightly` (aus), mit `gpgcheck=1` und `repo_gpgcheck=1`.
Die Reihenfolge ist wichtig, weil das Signieren eines Pakets dessen Prüfsumme ändert: `fetch-releases.sh` (`FETCH_EXT=rpm`) -> `sign-rpm.sh ... packages DIR` (rpmsign, Schlüssel-Job) ->
`build-rpm.sh RPMDIR stable|nightly OUTDIR` (repodata mit `createrepo_rs` 0.1.9, GPL-2.0, nur CI, nie ausgeliefert; Rückfall `CREATEREPO=createrepo_c`) -> `sign-rpm.sh ... repo rpm/<kanal>` (`repomd.xml.asc`).
`gate-createrepo.sh` vergleicht createrepo_rs mit createrepo_c an denselben RPMs und nennt das zu nutzende Werkzeug.
Lokales Gate (podman, Wegwerf-Fedora-Container, Wegwerf-Schlüssel nur darin): `scripts/test-rpm-container.sh RPMDIR`. Es prüft: Installation klappt; manipuliertes Paket, manipuliertes repomd.xml und unsigniertes Paket werden aus dem richtigen Grund abgelehnt;
Verzeichniseigentum je Paket samt Requires-Kette (`unowned-dirs.sh`, Befund UNOWNED bleibt benannt sichtbar); rpmlint (jedes E = rot, W erlaubt).

## GitHub Pages einschalten (Eigentümer, einmalig; nicht durch Agenten)

Repository `FreeSynergy-Net/Repository` > Settings > Pages > Build and deployment > Source: **GitHub Actions**. Dann den Workflow `publish` starten (Actions > publish > Run workflow, `deploy` anhaken).
