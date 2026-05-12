#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# shellcheck source=packages/pseudo-design-ca-tools/config.sh
. "$script_dir/config.sh"

usage() {
  cat <<'EOF'
Usage: pseudo-design-ca-mint-token HOST CA_DIR

Mint a short-lived, host-bound enrollment token for HOST using the offline
device enrollment provisioner in CA_DIR. The token is printed to stdout.
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

host="$1"
ca_dir="$(CDPATH= cd -- "$2" && pwd -P)"

case "$host" in
  *[!A-Za-z0-9.-]* | "" | .* | *..* | *.)
    die "invalid host name: $host"
    ;;
esac

require_file "$ca_dir/root_ca.crt"
require_file "$ca_dir/device-enrollment.key.json"
require_file "$ca_dir/provisioner-password"

step ca token "device:$host" \
  --offline \
  --issuer "$PSEUDO_DESIGN_CA_PROVISIONER_NAME" \
  --key "$ca_dir/device-enrollment.key.json" \
  --provisioner-password-file "$ca_dir/provisioner-password" \
  --san "$host.devices.$PSEUDO_DESIGN_CA_DOMAIN" \
  --san "spiffe://$PSEUDO_DESIGN_CA_DOMAIN/device/$host" \
  --not-after "$PSEUDO_DESIGN_ENROLLMENT_TOKEN_DURATION" \
  --ca-url "$PSEUDO_DESIGN_CA_URL" \
  --root "$ca_dir/root_ca.crt"
