# Sisyphus ArachOS Package Repository

This is the signed x86_64 package feed maintained by SisyphusAeolides for
ArachOS and compatible mkosi systems. The build and image path is mkosi;
there is no Arch or `pacman` dependency in this repository.

The archives and repository index use Arch's package format so mkosi can
assemble a reproducible live image. On an installed ArachOS system, Corinth is
the supported package interface; use its search, install, update, and remove
commands instead of calling a distribution package client directly.

This repository publishes x86_64 packages for:

- `iwchaos`
- `blerust`
- `ccze-rs`
- `elan-guardian`
- `libinput-rs`
- `tuned-rs`


Add the repository to `/etc/pacman.conf`:

```ini
[sisyphus]
SigLevel = Required DatabaseRequired
Server = https://sisyphusaeolides.github.io/Sisyphus-Repo/$arch
```

Install the repository key before refreshing the database. Check the
fingerprint independently before adding or locally trusting the key:

```sh
curl --fail --location --output sisyphus-repo.asc \
  https://raw.githubusercontent.com/SisyphusAeolides/Sisyphus-Repo/main/keys/sisyphus-repo.asc
gpg --show-keys --with-fingerprint --keyid-format long sisyphus-repo.asc
# Expected primary fingerprint: A31AA80E123526D235385F4F590D7A398A6D75BB
sudo pacman-key --add sisyphus-repo.asc
sudo pacman-key --lsign-key A31AA80E123526D235385F4F590D7A398A6D75BB
sudo pacman -Syy
sudo pacman -S blerust ccze-rs elan-guardian iwchaos libinput-rs tuned-rs
```

The commands above are for preparing an mkosi build host. A running ArachOS
installation consumes the same signed feed through Corinth:

```sh
corinth search iwchaos
corinth install iwchaos
corinth update iwchaos
corinth remove iwchaos
```

`SigLevel = Required DatabaseRequired` rejects unsigned packages and unsigned
repository databases. Do not change it to `Optional` or `TrustAll`.

Each published repository state also has a signed, immutable package snapshot
at `https://sisyphusaeolides.github.io/Sisyphus-Repo/snapshots/<commit-sha>/`.
It retains the exact package archives, detached signatures, database, and
signed checksum manifest. The manifest records its source commit, workflow
run, timestamp, and SHA-256 checksums. The publishing workflow refuses to
replace an existing snapshot.

The packages replace their corresponding `-git` names. `blerust` replaces
`blesh`, `ccze-rs` replaces `ccze`, `iwchaos` replaces in-tree `iwlwifi` and
`iwlmvm`, `libinput-rs` replaces `libinput`, and `tuned-rs` replaces `tuned`
and `power-profiles-daemon` when those packages are installed.

## ArachOS release feed

The ArachOS release packages are published in a separate path so their
database never overlaps the Sisyphus feed above. ArachOS installations use:

```ini
[arachos]
SigLevel = Required DatabaseRequired
Server = https://sisyphusaeolides.github.io/Sisyphus-Repo/arachos/$arch
```

The same signing key is used. Verify the fingerprint shown above before
trusting it, then refresh the database with `sudo pacman -Syy`. The feed
contains the Arach-Kernel, RustD, RustD-resolved, Hermes, Arach-HWD, Corinth,
Calamares, GRUB, and supporting ArachOS packages used to compose the live
image. Corinth remains the normal user-facing interface for installing and
updating them.

A release builder can publish a checked package directory with:

```sh
ARACHOS_GPG_KEY_ID=A31AA80E123526D235385F4F590D7A398A6D75BB \
  scripts/publish-arachos-repo.sh /path/to/packages
```

The publisher refuses to replace an archive with different bytes, signs every
package and the repository database, verifies those signatures, and writes a
checksum manifest alongside the feed.
