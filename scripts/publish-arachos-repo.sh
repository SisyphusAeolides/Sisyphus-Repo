#!/usr/bin/env bash
# Publish a signed ArachOS package feed beside the existing Sisyphus feed.
set -Eeuo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INPUT=${1:?usage: publish-arachos-repo.sh PACKAGE_DIRECTORY [OUTPUT_DIRECTORY]}
OUTPUT=${2:-$ROOT/arachos/x86_64}
KEY_ID=${ARACHOS_GPG_KEY_ID:?set ARACHOS_GPG_KEY_ID to the repository signing key}
GPG_HOME=${ARACHOS_GPG_HOME:-${GNUPGHOME:-$HOME/.gnupg}}

fail() { printf 'ArachOS repository: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"; }

INPUT=$(realpath -e "$INPUT") || fail "package directory is missing: $INPUT"
OUTPUT=$(realpath -m "$OUTPUT")
[[ -d "$INPUT" ]] || fail "package input is not a directory: $INPUT"

for command in gpg repo-add bsdtar sha256sum cmp install find sort; do
  need "$command"
done

mapfile -d '' archives < <(
  # Debug split packages stay available in the builder output but are not
  # needed by an installed system or the live-image composition. Keeping
  # them out of this feed avoids shipping hundreds of megabytes of symbols.
  find "$INPUT" -maxdepth 1 -type f -name '*.pkg.tar.zst' \
    ! -name '*-debug-*' -print0 | sort -z -V
)
((${#archives[@]} > 0)) || fail "no package archives found in $INPUT"

mkdir -p "$OUTPUT"
for source in "${archives[@]}"; do
  name=$(basename "$source")
  destination="$OUTPUT/$name"
  if [[ -e "$destination" ]] && ! cmp -s "$source" "$destination"; then
    fail "refusing to replace an existing archive with different contents: $destination"
  fi
  install -m 0644 "$source" "$destination"
  GNUPGHOME="$GPG_HOME" gpg --batch --yes --local-user "$KEY_ID" \
    --detach-sign --output "$destination.sig" "$destination"
done

pushd "$OUTPUT" >/dev/null
mapfile -t published < <(find . -maxdepth 1 -type f -name '*.pkg.tar.zst' -printf '%f\n' | sort -V)
((${#published[@]} > 0)) || fail "repository output contains no archives: $OUTPUT"

db=arachos.db.tar.gz
repo_args=(--sign --key "$KEY_ID")
if [[ -s "$db" && -s "$db.sig" ]]; then
  repo_args+=(--verify)
fi
GNUPGHOME="$GPG_HOME" repo-add "${repo_args[@]}" "$db" "${published[@]}"

# repo-add keeps rollback copies beside the active database. They are useful
# on a builder, but they are not part of the feed and only add stale bytes to
# the Pages tree.
for stale in \
  arachos.db.tar.gz.old arachos.db.tar.gz.old.sig \
  arachos.files.tar.gz.old arachos.files.tar.gz.old.sig; do
  [[ -e "$stale" ]] && rm -f -- "$stale"
done

for archive in "${published[@]}"; do
  [[ -s "$archive.sig" ]] || fail "missing package signature: $archive.sig"
  GNUPGHOME="$GPG_HOME" gpg --batch --verify "$archive.sig" "$archive" >/dev/null
done
[[ -s "$db.sig" ]] || fail "repo-add did not create a database signature"
GNUPGHOME="$GPG_HOME" gpg --batch --verify "$db.sig" "$db" >/dev/null

sha256sum "${published[@]}" "$db" "$db.sig" > arachos-checksums.sha256
popd >/dev/null

printf 'ArachOS repository written to %s (%d archives)\n' "$OUTPUT" "${#published[@]}"
