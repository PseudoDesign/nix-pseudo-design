#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# shellcheck source=packages/pseudo-design-ca-tools/config.sh
. "$script_dir/config.sh"

usage() {
  cat <<'EOF'
Usage: pseudo-design-ca-sign-intermediate CSR OUT_CERT CA_DIR

Validate and sign an online CA host-generated intermediate CA CSR using the
offline root CA. Only the signed certificate should be transferred back to the
online CA host.
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

validate_csr_key() {
  local csr_text="$1"
  local expected_curve

  case "$PSEUDO_DESIGN_CA_KEY_TYPE:$PSEUDO_DESIGN_CA_CURVE" in
    EC:P-256)
      expected_curve="ASN1 OID: prime256v1"
      ;;
    EC:P-384)
      expected_curve="ASN1 OID: secp384r1"
      ;;
    EC:P-521)
      expected_curve="ASN1 OID: secp521r1"
      ;;
    *)
      die "unsupported configured intermediate key type/curve: $PSEUDO_DESIGN_CA_KEY_TYPE/$PSEUDO_DESIGN_CA_CURVE"
      ;;
  esac

  grep -q "Public Key Algorithm: id-ecPublicKey" "$csr_text" \
    || die "CSR key type does not match configured type: $PSEUDO_DESIGN_CA_KEY_TYPE"
  grep -q "$expected_curve" "$csr_text" \
    || die "CSR curve does not match configured curve: $PSEUDO_DESIGN_CA_CURVE"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

[ "$#" -eq 3 ] || {
  usage >&2
  exit 2
}

need_command openssl
need_command step

csr_file="$1"
out_cert="$2"
ca_dir="$(CDPATH= cd -- "$3" && pwd -P)"
out_dir="$(dirname -- "$out_cert")"

require_file "$csr_file"
require_file "$ca_dir/root_ca.crt"
require_file "$ca_dir/root_ca.key"
require_file "$ca_dir/root-password"
[ ! -e "$out_cert" ] || die "refusing to overwrite existing file: $out_cert"
[ -d "$out_dir" ] || die "missing output directory: $out_dir"

openssl req -in "$csr_file" -noout -verify >/dev/null 2>&1 \
  || die "CSR self-signature verification failed"

subject="$(openssl req -in "$csr_file" -noout -subject -nameopt RFC2253)"
expected_subject="subject=CN=$PSEUDO_DESIGN_CA_INTERMEDIATE_NAME"
[ "$subject" = "$expected_subject" ] \
  || die "CSR subject mismatch: expected '$expected_subject', got '$subject'"

csr_text="$(mktemp)"
signed_cert="$(mktemp "$out_dir/intermediate_ca.crt.XXXXXX")"
trap 'rm -f "$csr_text" "$signed_cert"' EXIT

openssl req -in "$csr_file" -noout -text > "$csr_text"
validate_csr_key "$csr_text"

step certificate sign \
  --profile intermediate-ca \
  --path-len 0 \
  --password-file "$ca_dir/root-password" \
  "$csr_file" \
  "$ca_dir/root_ca.crt" \
  "$ca_dir/root_ca.key" > "$signed_cert"

openssl verify -CAfile "$ca_dir/root_ca.crt" "$signed_cert" >/dev/null
install -m 0644 "$signed_cert" "$out_cert"

cat <<EOF
Signed online intermediate CA certificate:
  $out_cert
EOF
