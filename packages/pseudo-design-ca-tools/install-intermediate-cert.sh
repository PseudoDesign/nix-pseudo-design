#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: pseudo-design-ca-install-intermediate-cert CERT CA_STATE_DIR

Verify and install a signed intermediate CA certificate into CA_STATE_DIR.
The local intermediate key must already exist in CA_STATE_DIR/secrets.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

require_file() {
  [ -s "$1" ] || die "missing required file: $1"
}

maybe_chown() {
  if [ -n "${PSEUDO_DESIGN_STEP_CA_OWNER:-}" ]; then
    chown "$PSEUDO_DESIGN_STEP_CA_OWNER" "$@"
  fi
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

[ "$#" -eq 2 ] || {
  usage >&2
  exit 2
}

need_command openssl

cert_source="$1"
state_dir="$2"
certs_dir="$state_dir/certs"
secrets_dir="$state_dir/secrets"
root_file="$certs_dir/root_ca.crt"
cert_file="$certs_dir/intermediate_ca.crt"
key_file="$secrets_dir/intermediate_ca.key"

require_file "$cert_source"
require_file "$root_file"
require_file "$key_file"
[ ! -e "$cert_file" ] || die "refusing to overwrite existing file: $cert_file"

openssl verify -CAfile "$root_file" "$cert_source" >/dev/null

cert_pub="$(mktemp)"
key_pub="$(mktemp)"
trap 'rm -f "$cert_pub" "$key_pub"' EXIT
openssl x509 -in "$cert_source" -noout -pubkey > "$cert_pub"
openssl pkey -in "$key_file" -pubout > "$key_pub"
cmp -s "$cert_pub" "$key_pub" || die "certificate does not match local intermediate key"

install -d -m 0750 "$certs_dir"
maybe_chown "$certs_dir"
install -m 0644 "$cert_source" "$cert_file"
maybe_chown "$cert_file"

cat <<EOF
Installed signed intermediate CA certificate:
  $cert_file
EOF
