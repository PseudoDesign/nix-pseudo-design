#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: pseudo-design-ca-export CA_DIR EXPORT_DIR

Copy CA artifacts from CA_DIR into EXPORT_DIR for removable-media transfer.

EXPORT_DIR/public contains commit-safe public artifacts.
EXPORT_DIR/mako contains online CA material to stage onto mako.
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

[ "$#" -eq 2 ] || {
  usage >&2
  exit 2
}

[ -d "$1" ] || die "missing CA directory: $1"
install -d -m 0700 "$2"

ca_dir="$(CDPATH= cd -- "$1" && pwd -P)"
export_dir="$(CDPATH= cd -- "$2" && pwd -P)"
public_dir="$export_dir/public"
mako_dir="$export_dir/mako"

require_file "$ca_dir/root_ca.crt"
require_file "$ca_dir/root_ca.fingerprint"
require_file "$ca_dir/device-enrollment.pub.json"
require_file "$ca_dir/intermediate_ca.crt"
require_file "$ca_dir/intermediate_ca.key"
require_file "$ca_dir/intermediate-password"

install -d -m 0755 "$public_dir"
install -m 0644 "$ca_dir/root_ca.crt" "$public_dir/root_ca.crt"
install -m 0644 "$ca_dir/root_ca.fingerprint" "$public_dir/root_ca.fingerprint"
install -m 0644 "$ca_dir/device-enrollment.pub.json" "$public_dir/device-enrollment.pub.json"

install -d -m 0700 "$mako_dir"
install -m 0600 "$ca_dir/root_ca.crt" "$mako_dir/root_ca.crt"
install -m 0600 "$ca_dir/intermediate_ca.crt" "$mako_dir/intermediate_ca.crt"
install -m 0600 "$ca_dir/intermediate_ca.key" "$mako_dir/intermediate_ca.key"
install -m 0600 "$ca_dir/intermediate-password" "$mako_dir/intermediate-password"

cat <<EOF
Exported CA artifacts:
  $public_dir
  $mako_dir
EOF
