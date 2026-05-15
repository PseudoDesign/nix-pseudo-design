#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
default_repo_root="$(CDPATH= cd -- "$script_dir/../.." && pwd -P)"
if [ -f "$default_repo_root/flake.nix" ]; then
  repo_root="${PSEUDO_DESIGN_REPO_ROOT:-$default_repo_root}"
else
  repo_root="${PSEUDO_DESIGN_REPO_ROOT:-$(pwd -P)}"
fi

usage() {
  cat <<'EOF'
Usage: pseudo-design-ca-install-public-artifacts CA_DIR_OR_PUBLIC_DIR

Copy public CA artifacts from CA_DIR or an exported public artifact directory
into this repository. These files are safe to commit and are consumed by the
NixOS configuration when present.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_file() {
  [ -s "$1" ] || die "missing required file: $1"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

[ "$#" -eq 1 ] || {
  usage >&2
  exit 2
}

ca_dir="$(CDPATH= cd -- "$1" && pwd -P)"

[ -f "$repo_root/flake.nix" ] || die "run from the repo root or set PSEUDO_DESIGN_REPO_ROOT"

require_file "$ca_dir/root_ca.crt"
require_file "$ca_dir/root_ca.fingerprint"
require_file "$ca_dir/device-enrollment.pub.json"

install -d -m 0755 "$repo_root/ca/public"
install -m 0644 "$ca_dir/root_ca.crt" "$repo_root/ca/public/root_ca.crt"
install -m 0644 "$ca_dir/root_ca.fingerprint" "$repo_root/ca/public/root_ca.fingerprint"
install -m 0644 "$ca_dir/device-enrollment.pub.json" "$repo_root/ca/public/device-enrollment.pub.json"

cat <<EOF
Installed public CA artifacts:
  ca/public/root_ca.crt
  ca/public/root_ca.fingerprint
  ca/public/device-enrollment.pub.json
EOF
