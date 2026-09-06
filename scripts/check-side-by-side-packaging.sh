#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Enforce native-only RustD packaging and reversible migration contracts.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

is_forbidden_identity() {
  local identity="${1%%[<>=]*}"
  [[ "$identity" == systemd || "$identity" == systemd-* || "$identity" == udev ]]
}

allowed_replacement_identity() {
  local src="$1" key="$2" value="${3%%[<>=]*}"
  case "$src:$key:$value" in
    */rustd/PKGBUILD:provides:systemd-libs|\
    */rustd/PKGBUILD:conflicts:systemd-libs|\
    */rustd/PKGBUILD:replaces:systemd-libs|\
    */rustd/.SRCINFO:provides:systemd-libs|\
    */rustd/.SRCINFO:conflicts:systemd-libs|\
    */rustd/.SRCINFO:replaces:systemd-libs|\
    */rustd-resolved/PKGBUILD:conflicts:systemd-resolved|\
    */rustd-resolved/PKGBUILD:replaces:systemd-resolved|\
    */rustd-resolved/.SRCINFO:conflicts:systemd-resolved|\
    */rustd-resolved/.SRCINFO:replaces:systemd-resolved)
      return 0
      ;;
  esac
  return 1
}

check_metadata() {
  local pb="$1" src="$2" value key field
  local -a values=()

  mapfile -t values < <(
    bash -c '
      source "$1"
      for field in depends provides conflicts replaces; do
        declare -n entries="$field"
        for value in "${entries[@]-}"; do
          printf "%s\t%s\n" "$field" "$value"
        done
      done
    ' _ "$pb"
  )
  for value in "${values[@]}"; do
    IFS=$'\t' read -r field value <<<"$value"
    [[ -z "$value" ]] || allowed_replacement_identity "$pb" "$field" "$value" \
      || ! is_forbidden_identity "$value" \
      || fail "$pb declares forbidden package identity: $value"
  done

  while IFS=' = ' read -r key value; do
    case "$key" in
      depends|provides|conflicts|replaces)
        allowed_replacement_identity "$src" "$key" "$value" \
          || ! is_forbidden_identity "$value" \
          || fail "$src declares forbidden package identity: $value"
        ;;
    esac
  done <"$src"
}

tree_is_native() {
  local root="$1" path rel target
  while IFS= read -r -d '' path; do
    rel="${path#"$root"/}"
    case "/$rel" in
      */systemd|*/systemd/*|*/systemctl|*/journalctl|*/udevadm|*/systemd-*|*/pam_systemd.so|*/libnss_resolve.so.2)
        echo "forbidden packaged path: $rel" >&2
        return 1
        ;;
    esac
    if [[ -L "$path" ]]; then
      target="$(readlink "$path")"
      case "/$target" in
        */systemd|*/systemd/*|*/systemctl|*/journalctl|*/udevadm|*/systemd-*|*/pam_systemd.so|*/libnss_resolve.so.2)
          echo "forbidden packaged symlink target: $rel -> $target" >&2
          return 1
          ;;
      esac
    fi
  done < <(find "$root" -mindepth 1 -print0)

  if [[ -f "$root/.PKGINFO" ]]; then
    local pkgname
    pkgname="$(awk -F ' = ' '$1 == "pkgname" { print $2; exit }' "$root/.PKGINFO")"
    while IFS=' = ' read -r key value; do
      case "$key" in
        depend|provides|conflict|replaces)
          if [[ "$pkgname" == rustd-compat && "$value" == systemd-libs \
                && "$key" =~ ^(provides|conflict|replaces)$ ]]; then
            continue
          fi
          if [[ "$pkgname" == rustd-resolved && "$value" == systemd-resolved \
                && "$key" =~ ^(conflict|replaces)$ ]]; then
            continue
          fi
          ! is_forbidden_identity "$value" || {
            echo "forbidden package archive identity: $value" >&2
            return 1
          }
          ;;
      esac
    done <"$root/.PKGINFO"
  fi

  if [[ -f "$root/usr/share/rustd-resolved/nsswitch.conf.fragment" ]]; then
    grep -Eq '(^|[[:space:]])rustd_dns([[:space:]]|$)' \
      "$root/usr/share/rustd-resolved/nsswitch.conf.fragment" || {
        echo "resolver package lacks native NSS configuration" >&2
        return 1
      }
    ! grep -Eq '(^|[[:space:]])resolve([[:space:]]|$)' \
      "$root/usr/share/rustd-resolved/nsswitch.conf.fragment" || {
        echo "resolver package retains compatibility NSS configuration" >&2
        return 1
      }
    ! grep -Eq '(^|[[:space:]])rustd_resolve([[:space:]]|$)' \
      "$root/usr/share/rustd-resolved/nsswitch.conf.fragment" || {
        echo "resolver package retains transitional NSS configuration" >&2
        return 1
      }
  fi
}

check_package_artifact() {
  local artifact="$1" work="$2" tree
  if [[ -d "$artifact" ]]; then
    tree="$artifact"
  else
    tree="$work/artifact-$RANDOM"
    mkdir -p "$tree"
    bsdtar -xf "$artifact" -C "$tree"
  fi
  tree_is_native "$tree" || fail "native purity rejected $artifact"
  pass "native package artifact: $artifact"
}

check_pkgbuild() {
  local dir="$1"
  local name="$2"
  local commit="$3"
  local pb="$ROOT/$dir/PKGBUILD"
  local src="$ROOT/$dir/.SRCINFO"

  [[ -f "$pb" ]] || fail "missing $pb"
  [[ -f "$src" ]] || fail "missing $src"

  grep -Fq "_commit=$commit" "$pb" || fail "$name PKGBUILD commit pin mismatch"
  grep -Fq "commit=$commit" "$src" || fail "$name .SRCINFO commit pin mismatch"
  check_metadata "$pb" "$src"
  pass "$name source pin and metadata contract"
}

check_boot_assets() {
  local dir="$ROOT/rustd"
  [[ -f "$dir/rustd-configure-boot" ]] || fail "missing rustd-configure-boot"
  [[ -f "$dir/rustd-boot-entry.conf" ]] || fail "missing rustd-boot-entry.conf"
  grep -Fq 'init=/usr/lib/rustd/rustd' "$dir/rustd-configure-boot" \
    || fail "boot script missing RustD init="
  grep -Fq 'init=/usr/lib/rustd/rustd' "$dir/rustd-boot-entry.conf" \
    || fail "boot entry missing RustD init="
  bash -n "$dir/rustd-configure-boot"
  grep -Fq 'schema-version' "$dir/rustd-configure-boot" \
    || fail "boot script lacks versioned state"
  grep -Fq 'rustd-rollback.conf' "$dir/rustd-configure-boot" \
    || fail "boot script lacks persistent rollback entry"
  ! grep -Eq 'rustd-configure-boot.*\|\|[[:space:]]*true' "$dir/rustd.install" \
    || fail "boot migration failure is suppressed"
  pass "RustD transactional boot assets"
}

check_pkgbuild rustd rustd a50abcb6c23c0f69c5fe4e156a1a0e7db32b32d7
check_pkgbuild rustd-resolved rustd-resolved f2f6cc1a81b6adc9f5320be4cab5de9eb24b6f72
check_boot_assets

grep -Fq 'package_rustd-libs' "$ROOT/rustd/PKGBUILD" \
  || fail "rustd PKGBUILD lacks rustd-libs split package"
grep -Fq 'package_rustd-devel' "$ROOT/rustd/PKGBUILD" \
  || fail "rustd PKGBUILD lacks rustd-devel split package"
grep -Fq 'package_rustd-compat' "$ROOT/rustd/PKGBUILD" \
  || fail "rustd PKGBUILD lacks rustd-compat split package"
grep -Fq 'librustd_service' "$ROOT/rustd/PKGBUILD" \
  || fail "rustd-libs does not install librustd_service"
! grep -Eq "provides=.*systemd-libs|replaces=.*systemd-libs" "$ROOT/rustd/PKGBUILD" \
  || fail "preview rustd-compat must not claim complete systemd-libs ABI"
! grep -Eq "depends=.*rustd-compat" "$ROOT/rustd/PKGBUILD" \
  || fail "rustd must not force the preview compatibility package"
pass "rustd-libs/compat/devel split packaging contract"

for dir in libinput-rs tuned-rs elan-guardian; do
  pb="$ROOT/$dir/PKGBUILD"
  [[ -f "$pb" ]] || fail "missing $pb"
  ! grep -Eq "systemd-libs" "$pb" \
    || fail "$dir still depends on systemd-libs"
done
grep -Fq 'rustd-libs' "$ROOT/libinput-rs/PKGBUILD" \
  || fail "libinput-rs was not retargeted onto rustd-libs"
grep -Fq 'rustd-libs' "$ROOT/tuned-rs/PKGBUILD" \
  || fail "tuned-rs was not retargeted onto rustd-libs"
grep -Fq '/usr/lib/rustd/system' "$ROOT/elan-guardian/PKGBUILD" \
  || fail "elan-guardian units were not moved onto /usr/lib/rustd/system"
pass "first-party packages retargeted off systemd-libs"

[[ -f "$ROOT/native-cutover-tiers.txt" ]] \
  || fail "missing native-cutover-tiers.txt"
[[ -f "$ROOT/scripts/check-consumer-tiers.sh" ]] \
  || fail "missing check-consumer-tiers.sh"
bash "$ROOT/scripts/check-consumer-tiers.sh" --tier T0
bash "$ROOT/scripts/check-consumer-tiers.sh" --tier T1
bash "$ROOT/scripts/check-consumer-tiers.sh" --tier T2 --list >/dev/null
bash "$ROOT/scripts/check-consumer-tiers.sh" --tier T3 --list >/dev/null
pass "consumer tier DAG and gates present"

! grep -Eq '(^|[/[:space:]])(systemctl|journalctl|udevadm)([[:space:]]|$)' \
  "$ROOT/rustd/PKGBUILD" "$ROOT/rustd/rustd-udev.install" "$ROOT/rustd/rustd-udev.hook" \
  || fail "RustD package assets invoke a compatibility command alias"
grep -Fq '/usr/bin/rustudevadm' "$ROOT/rustd/rustd-udev.install" \
  || fail "initramfs install hook does not package rustudevadm"
grep -Fq 'rustd_dns' "$ROOT/rustd-resolved/rustd-resolved.install" \
  || fail "resolver install hook does not select the native NSS module"
grep -Fq "_rustd_nss_name=rustd_dns" "$ROOT/rustd-resolved/PKGBUILD" \
  || fail "resolver PKGBUILD does not select the native NSS module"
grep -Fq 'libnss_${_rustd_nss_name}.so.2' "$ROOT/rustd-resolved/PKGBUILD" \
  || fail "resolver does not package its native NSS module"
pass "native-only commands and NSS policy"

# Simulate transactional boot entry apply and removal.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/native/usr/bin" "$work/native/usr/lib/rustd/system"
touch "$work/native/usr/bin/rustctl" \
  "$work/native/usr/bin/rustjournalctl" \
  "$work/native/usr/bin/rustudevadm" \
  "$work/native/usr/lib/rustd/system/rustd-udevd.service"
tree_is_native "$work/native" || fail "native package fixture was rejected"

mkdir -p "$work/forbidden/usr/bin"
ln -s rustctl "$work/forbidden/usr/bin/systemctl"
if tree_is_native "$work/forbidden" 2>/dev/null; then
  fail "purity gate accepted a compatibility symlink"
fi
rm -rf "$work/forbidden"
mkdir -p "$work/forbidden/usr/lib/rustd/system"
touch "$work/forbidden/usr/lib/rustd/system/systemd-udevd.service"
if tree_is_native "$work/forbidden" 2>/dev/null; then
  fail "purity gate accepted a compatibility unit"
fi
pass "native package tree simulation rejects compatibility files and symlinks"

cat >"$work/nsswitch.conf" <<'EOF'
passwd: files
hosts: files myhostname resolve [!UNAVAIL=return] dns
EOF
RUSTD_RESOLVED_NSSWITCH="$work/nsswitch.conf" \
  bash -c 'source "$1"; post_install' _ \
  "$ROOT/rustd-resolved/rustd-resolved.install"
grep -Eq '^hosts:.*[[:space:]]rustd_dns([[:space:]]|$)' "$work/nsswitch.conf" \
  || fail "resolver install hook did not activate the native NSS name"
! grep -Eq '^hosts:.*[[:space:]]resolve([[:space:]]|$)' "$work/nsswitch.conf" \
  || fail "resolver install hook retained the compatibility NSS name"
if RUSTD_RESOLVED_NSS_NAME=resolve \
  RUSTD_RESOLVED_NSSWITCH="$work/nsswitch.conf" \
  bash -c 'source "$1"; post_install' _ \
    "$ROOT/rustd-resolved/rustd-resolved.install" 2>/dev/null; then
  fail "resolver install hook accepted the compatibility NSS name"
fi
cat >"$work/nsswitch-transitional.conf" <<'EOF'
passwd: files
hosts: files myhostname rustd_resolve [!UNAVAIL=return] dns
EOF
RUSTD_RESOLVED_NSSWITCH="$work/nsswitch-transitional.conf" \
  bash -c 'source "$1"; post_install' _ \
  "$ROOT/rustd-resolved/rustd-resolved.install"
grep -Eq '^hosts:.*[[:space:]]rustd_dns([[:space:]]|$)' "$work/nsswitch-transitional.conf" \
  || fail "resolver install hook did not migrate transitional rustd_resolve"
! grep -Eq '^hosts:.*[[:space:]]rustd_resolve([[:space:]]|$)' "$work/nsswitch-transitional.conf" \
  || fail "resolver install hook retained transitional rustd_resolve"
pass "resolver install hook migrates nsswitch to the native NSS name"

mkdir -p "$work/loader/entries" "$work/bootlib" "$work/state"
cp "$ROOT/rustd/rustd-boot-entry.conf" "$work/bootlib/rustd-boot-entry.conf"
cat >"$work/loader/entries/cachyos.conf" <<'EOF'
title   CachyOS
linux   /vmlinuz-linux-cachyos
initrd  /initramfs-linux-cachyos.img
options root=UUID=test rw quiet
EOF
cp "$work/loader/entries/cachyos.conf" "$work/original-entry"
RUSTD_LOADER_ENTRIES="$work/loader/entries" \
RUSTD_BOOT_CONF="$work/bootlib/rustd-boot-entry.conf" \
RUSTD_MIGRATION_STATE="$work/state" \
  bash "$ROOT/rustd/rustd-configure-boot"
grep -Fq 'init=/usr/lib/rustd/rustd' "$work/loader/entries/cachyos.conf" \
  || fail "primary entry did not select RustD"
[[ -f "$work/loader/entries/rustd-rollback.conf" ]] \
  || fail "did not create a rollback boot entry"
cmp -s "$work/original-entry" "$work/loader/entries/rustd-rollback.conf" \
  || fail "rollback boot entry does not preserve the original"
[[ "$(<"$work/state/schema-version")" == 1 ]] || fail "migration schema version missing"

RUSTD_LOADER_ENTRIES="$work/loader/entries" \
RUSTD_BOOT_CONF="$work/bootlib/rustd-boot-entry.conf" \
RUSTD_MIGRATION_STATE="$work/state" \
  bash "$ROOT/rustd/rustd-configure-boot" restore
cmp -s "$work/original-entry" "$work/loader/entries/cachyos.conf" \
  || fail "boot removal did not restore the original entry"
[[ ! -e "$work/loader/entries/rustd-rollback.conf" ]] \
  || fail "removal left a redundant rollback entry"
pass "boot migration apply and restore are reversible"

# Exercise mkinitcpio migration success/removal and failure rollback.
mkdir -p "$work/mkinitcpio/conf.d" "$work/bin" "$work/migration-state"
cat >"$work/mkinitcpio/mkinitcpio.conf" <<'EOF'
HOOKS=(base systemd sd-vconsole sd-encrypt filesystems)
EOF
cp "$work/mkinitcpio/mkinitcpio.conf" "$work/original-mkinitcpio"
cat >"$work/bin/mkinitcpio-ok" <<'EOF'
#!/bin/sh
test "$1" = -P
EOF
cat >"$work/bin/boot-helper" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$work/bin/mkinitcpio-ok" "$work/bin/boot-helper"
RUSTD_MIGRATION_STATE="$work/migration-state" \
RUSTD_MKINITCPIO_MAIN="$work/mkinitcpio/mkinitcpio.conf" \
RUSTD_MKINITCPIO_DROPINS="$work/mkinitcpio/conf.d" \
RUSTD_MKINITCPIO="$work/bin/mkinitcpio-ok" \
RUSTD_BOOT_HELPER="$work/bin/boot-helper" \
  bash -c 'source "$1"; post_install; pre_remove; pre_remove' _ "$ROOT/rustd/rustd.install"
cmp -s "$work/original-mkinitcpio" "$work/mkinitcpio/mkinitcpio.conf" \
  || fail "package removal did not restore mkinitcpio configuration"

rm -rf "$work/migration-state"
cat >"$work/bin/mkinitcpio-fail" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$work/bin/mkinitcpio-fail"
if RUSTD_MIGRATION_STATE="$work/migration-state" \
  RUSTD_MKINITCPIO_MAIN="$work/mkinitcpio/mkinitcpio.conf" \
  RUSTD_MKINITCPIO_DROPINS="$work/mkinitcpio/conf.d" \
  RUSTD_MKINITCPIO="$work/bin/mkinitcpio-fail" \
  RUSTD_BOOT_HELPER="$work/bin/boot-helper" \
    bash -c 'source "$1"; post_install' _ "$ROOT/rustd/rustd.install" \
      2>"$work/expected-failure"; then
  fail "mkinitcpio failure did not fail the package migration"
fi
grep -Fq 'pre-transaction initramfs configuration restored' "$work/expected-failure" \
  || fail "failed migration did not report transaction rollback"
cmp -s "$work/original-mkinitcpio" "$work/mkinitcpio/mkinitcpio.conf" \
  || fail "failed migration did not roll back mkinitcpio configuration"

rm -rf "$work/migration-state"
cat >"$work/bin/boot-fail" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$work/bin/boot-fail"
if RUSTD_MIGRATION_STATE="$work/migration-state" \
  RUSTD_MKINITCPIO_MAIN="$work/mkinitcpio/mkinitcpio.conf" \
  RUSTD_MKINITCPIO_DROPINS="$work/mkinitcpio/conf.d" \
  RUSTD_MKINITCPIO="$work/bin/mkinitcpio-ok" \
  RUSTD_BOOT_HELPER="$work/bin/boot-fail" \
    bash -c 'source "$1"; post_install' _ "$ROOT/rustd/rustd.install" \
      2>"$work/expected-boot-failure"; then
  fail "boot configuration failure did not fail the package migration"
fi
grep -Fq 'pre-transaction initramfs configuration restored' "$work/expected-boot-failure" \
  || fail "boot configuration failure did not report transaction rollback"
cmp -s "$work/original-mkinitcpio" "$work/mkinitcpio/mkinitcpio.conf" \
  || fail "boot configuration failure did not roll back mkinitcpio configuration"
pass "mkinitcpio and boot failures fail closed and restore transaction input"

for artifact in "$@"; do
  check_package_artifact "$artifact" "$work"
done

echo "All native-only production packaging checks passed."
