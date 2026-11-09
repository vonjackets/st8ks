#!/usr/bin/env bash
# Updates vendorHash in flake.nix after go.mod or go.sum changes.
#
#   hack/update-vendor-hash.sh
#
# It clears the hash, builds the Go modules so that Nix reports the hash it
# got, and writes that hash back. CI runs it on Dependabot pull requests.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLAKE="$ROOT/flake.nix"

set_hash() {
  local tmp
  tmp="$(mktemp)"
  sed -E "s|^( *vendorHash = )\"[^\"]*\";|\1\"$1\";|" "$FLAKE" > "$tmp"
  cat "$tmp" > "$FLAKE"
  rm -f "$tmp"
}

grep -qE '^ *vendorHash = "[^"]*";' "$FLAKE" || { echo "no vendorHash line in flake.nix" >&2; exit 1; }

old="$(sed -nE 's|^ *vendorHash = "([^"]*)";|\1|p' "$FLAKE")"
set_hash ""
out="$(nix build --no-link "$ROOT#st8ks.goModules" 2>&1 || true)"
new="$(printf '%s\n' "$out" | sed -nE 's|^ *got: *(sha256-[A-Za-z0-9+/=]+).*|\1|p' | tail -n1)"

if [ -z "$new" ]; then
  set_hash "$old"
  printf '%s\n' "$out" >&2
  echo "could not find the new vendorHash in the nix output" >&2
  exit 1
fi

set_hash "$new"
if [ "$new" = "$old" ]; then
  echo "vendorHash is up to date: $new"
else
  echo "vendorHash: $old -> $new"
fi
