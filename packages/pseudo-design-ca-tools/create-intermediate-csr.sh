#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# shellcheck source=packages/pseudo-design-ca-tools/config.sh
. "$script_dir/config.sh"

usage() {
  cat <<'EOF'
Usage: pseudo-design-ca-create-intermediate-csr CA_STATE_DIR

Generate the online intermediate CA private key and CSR in CA_STATE_DIR.
The private key is intentionally unencrypted and must remain on the online CA host.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

refuse_existing() {
  [ ! -e "$1" ] || die "refusing to overwrite existing file: $1"
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

[ "$#" -eq 1 ] || {
  usage >&2
  exit 2
}

need_command step

state_dir="$1"
certs_dir="$state_dir/certs"
secrets_dir="$state_dir/secrets"
csr_file="$certs_dir/intermediate_ca.csr"
cert_file="$certs_dir/intermediate_ca.crt"
key_file="$secrets_dir/intermediate_ca.key"

refuse_existing "$key_file"
refuse_existing "$cert_file"
refuse_existing "$csr_file"

install -d -m 0750 "$certs_dir" "$secrets_dir"
maybe_chown "$certs_dir" "$secrets_dir"

umask 077
step certificate create \
  "$PSEUDO_DESIGN_CA_INTERMEDIATE_NAME" \
  "$csr_file" \
  "$key_file" \
  --csr \
  --no-password \
  --insecure \
  --kty "$PSEUDO_DESIGN_CA_KEY_TYPE" \
  --curve "$PSEUDO_DESIGN_CA_CURVE"

chmod 0644 "$csr_file"
chmod 0600 "$key_file"
maybe_chown "$csr_file" "$key_file"

cat <<EOF
Generated online intermediate CA material:
  CSR: $csr_file
  Key: $key_file

Transfer only the CSR to the offline CA host for signing. Do not copy the key
off the online CA host.
EOF
