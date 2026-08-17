# Sisyphus Pacman Repository

This is the Arch Linux and compatible Arch-based distribution repository
maintained by SisyphusAeolides. Non-Arch package targets are intentionally
outside this repository's maintenance scope.

This repository publishes x86_64 packages for:

- `ccze-rs`
- `elan-guardian`
- `libinput-rs`
- `tuned-rs`
- `rustd`
- `rustd-resolved`


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
# Expected primary fingerprint: 2A02745D8C2C03AE7F95BCEA8136EB9238213447
sudo pacman-key --add sisyphus-repo.asc
sudo pacman-key --lsign-key 2A02745D8C2C03AE7F95BCEA8136EB9238213447
sudo pacman -Syy
sudo pacman -S ccze-rs elan-guardian libinput-rs tuned-rs rustd rustd-resolved
```

`SigLevel = Required DatabaseRequired` rejects unsigned packages and unsigned
repository databases. Do not change it to `Optional` or `TrustAll`.

Each published repository state also has a signed, immutable package snapshot
at `https://sisyphusaeolides.github.io/Sisyphus-Repo/snapshots/<commit-sha>/`.
It retains the exact package archives, detached signatures, database, and
signed checksum manifest. The manifest records its source commit, workflow
run, timestamp, and SHA-256 checksums. The publishing workflow refuses to
replace an existing snapshot.

The packages replace their corresponding `-git` names. `ccze-rs` replaces
`ccze`, `libinput-rs` replaces `libinput`, and `tuned-rs` replaces `tuned` and
`power-profiles-daemon` when those packages are installed.

RustD's native-only cutover is a coordinated repository transition, not a
drop-in package alias. The final repository will not provide systemd package
names, shared-library SONAMEs, commands, or protocols. Every package listed in
[`native-cutover-packages.txt`](native-cutover-packages.txt) must first be
rebuilt against RustD-native APIs or removed from the certified profile.
`scripts/audit-systemd-closure.py` compares that manifest with an installed
CachyOS system and inventories remaining ELF links:

```sh
python3 scripts/audit-systemd-closure.py \
  --manifest native-cutover-packages.txt \
  --output rustd-systemd-closure.json
```

RustD packages may be promoted only from exact source commits carrying passing
native-purity, installed-system, rollback, security, and performance
certificates against the frozen systemd v261 comparison image.
