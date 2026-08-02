# Sisyphus Pacman Repository

This repository publishes x86_64 packages for:

- `ccze-rs`
- `elan-guardian`
- `libinput-rs`
- `tuned-rs`

Add the repository to `/etc/pacman.conf`:

```ini
[sisyphus]
SigLevel = Optional TrustAll
Server = https://sisyphusaeolides.github.io/Sisyphus-Repo/$arch
```

Then refresh the database and install packages normally:

```sh
sudo pacman -Syy
sudo pacman -S ccze-rs elan-guardian libinput-rs tuned-rs
```

The packages replace their corresponding `-git` names. `ccze-rs` replaces
`ccze`, `libinput-rs` replaces `libinput`, and `tuned-rs` replaces `tuned`
and `power-profiles-daemon` when those packages are installed.
