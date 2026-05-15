#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
default_repo_root="$(CDPATH= cd -- "$script_dir/../.." && pwd -P)"
if [ -f "$default_repo_root/flake.nix" ]; then
  repo_root="${PSEUDO_DESIGN_REPO_ROOT:-$default_repo_root}"
else
  repo_root="${PSEUDO_DESIGN_REPO_ROOT:-$(pwd -P)}"
fi

# shellcheck source=packages/pseudo-design-ca-tools/config.sh
. "$script_dir/config.sh"

usage() {
  cat <<'EOF'
Usage: pseudo-design-ca-bootstrap CA_DIR

Create the pseudo.design root CA and device enrollment JWK provisioner in
CA_DIR. CA_DIR must be outside this repository.

The script is idempotent: existing complete artifacts are kept.

Set PSEUDO_DESIGN_CA_ROOT_KMS and PSEUDO_DESIGN_CA_ROOT_KEY to create and use
the offline root CA certificate with an existing KMS/HSM key. In that mode no
root_ca.key or root-password file is created. PSEUDO_DESIGN_CA_ROOT_CERT may be
set to a separate KMS certificate URI; it defaults to PSEUDO_DESIGN_CA_ROOT_KEY.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

ensure_complete_pair() {
  local first="$1"
  local second="$2"
  if [ -e "$first" ] && [ -e "$second" ]; then
    return 0
  fi
  if [ ! -e "$first" ] && [ ! -e "$second" ]; then
    return 1
  fi
  die "found only one of $first and $second; refusing to continue"
}

create_password_file() {
  local path="$1"
  if [ -e "$path" ]; then
    chmod 0600 "$path"
    printf 'Keeping existing password file: %s\n' "$path"
    return
  fi

  openssl rand -base64 48 > "$path"
  chmod 0600 "$path"
  printf 'Created password file: %s\n' "$path"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

[ "$#" -eq 1 ] || {
  usage >&2
  exit 2
}

need_command openssl
need_command step

ca_dir="$1"
mkdir -p "$ca_dir"
ca_dir="$(CDPATH= cd -- "$ca_dir" && pwd -P)"

case "$ca_dir/" in
  "$repo_root/"*)
    die "CA_DIR is inside the Git checkout; choose an offline/private directory outside $repo_root"
    ;;
esac

umask 077

root_uses_kms=0
case "${PSEUDO_DESIGN_CA_ROOT_KMS:-}:${PSEUDO_DESIGN_CA_ROOT_KEY:-}" in
  :)
    ;;
  *:)
    die "PSEUDO_DESIGN_CA_ROOT_KEY must be set when PSEUDO_DESIGN_CA_ROOT_KMS is set"
    ;;
  :*)
    die "PSEUDO_DESIGN_CA_ROOT_KMS must be set when PSEUDO_DESIGN_CA_ROOT_KEY is set"
    ;;
  *)
    root_uses_kms=1
    ;;
esac

if [ "$root_uses_kms" -eq 1 ]; then
  root_cert_uri="${PSEUDO_DESIGN_CA_ROOT_CERT:-$PSEUDO_DESIGN_CA_ROOT_KEY}"
  [ ! -e "$ca_dir/root_ca.key" ] || die "found file-backed root key in KMS mode: $ca_dir/root_ca.key"
  [ ! -e "$ca_dir/root-password" ] || die "found file-backed root password in KMS mode: $ca_dir/root-password"
else
  create_password_file "$ca_dir/root-password"
fi

create_password_file "$ca_dir/provisioner-password"

if [ "$root_uses_kms" -eq 1 ]; then
  if [ -s "$ca_dir/root_ca.crt" ]; then
    printf 'Keeping existing KMS-backed root CA certificate: %s\n' "$ca_dir/root_ca.crt"
  else
    step certificate create \
      "$PSEUDO_DESIGN_CA_ROOT_NAME" \
      "$ca_dir/root_ca.crt" \
      --profile root-ca \
      --kms "$PSEUDO_DESIGN_CA_ROOT_KMS" \
      --key "$PSEUDO_DESIGN_CA_ROOT_KEY"
    chmod 0644 "$ca_dir/root_ca.crt"
  fi

  if step kms certificate \
    --kms "$PSEUDO_DESIGN_CA_ROOT_KMS" \
    "$root_cert_uri" >/dev/null 2>&1; then
    printf 'Keeping existing KMS root CA certificate object: %s\n' "$root_cert_uri"
  else
    step kms certificate \
      --import "$ca_dir/root_ca.crt" \
      --kms "$PSEUDO_DESIGN_CA_ROOT_KMS" \
      "$root_cert_uri" >/dev/null
  fi
else
  if ensure_complete_pair "$ca_dir/root_ca.crt" "$ca_dir/root_ca.key"; then
    printf 'Keeping existing root CA: %s\n' "$ca_dir/root_ca.crt"
  else
    step certificate create \
      "$PSEUDO_DESIGN_CA_ROOT_NAME" \
      "$ca_dir/root_ca.crt" \
      "$ca_dir/root_ca.key" \
      --profile root-ca \
      --kty "$PSEUDO_DESIGN_CA_KEY_TYPE" \
      --curve "$PSEUDO_DESIGN_CA_CURVE" \
      --password-file "$ca_dir/root-password"
    chmod 0644 "$ca_dir/root_ca.crt"
    chmod 0600 "$ca_dir/root_ca.key"
  fi
fi

if ensure_complete_pair "$ca_dir/device-enrollment.pub.json" "$ca_dir/device-enrollment.key.json"; then
  printf 'Keeping existing enrollment provisioner JWK: %s\n' "$ca_dir/device-enrollment.pub.json"
else
  step crypto jwk create \
    "$ca_dir/device-enrollment.pub.json" \
    "$ca_dir/device-enrollment.key.json" \
    --kty "$PSEUDO_DESIGN_CA_KEY_TYPE" \
    --crv "$PSEUDO_DESIGN_CA_CURVE" \
    --use sig \
    --password-file "$ca_dir/provisioner-password"
  chmod 0644 "$ca_dir/device-enrollment.pub.json"
  chmod 0600 "$ca_dir/device-enrollment.key.json"
fi

step certificate fingerprint "$ca_dir/root_ca.crt" > "$ca_dir/root_ca.fingerprint"
chmod 0644 "$ca_dir/root_ca.fingerprint"

if [ -n "${PSEUDO_DESIGN_CA_BOOTSTRAP_NEXT:-}" ]; then
  next_command="$PSEUDO_DESIGN_CA_BOOTSTRAP_NEXT"
elif [ -f "$repo_root/flake.nix" ]; then
  next_command="nix run \"$repo_root#ca-install-public-artifacts\" -- \"$ca_dir\""
else
  next_command="nix run .#ca-install-public-artifacts -- \"$ca_dir\""
fi

cat <<EOF

Offline CA state is ready in:
  $ca_dir

Private/offline files:
EOF

if [ "$root_uses_kms" -eq 1 ]; then
  cat <<EOF
  root signing key in configured KMS/HSM
  device-enrollment.key.json
  provisioner-password
EOF
else
  cat <<EOF
  root_ca.key
  root-password
  device-enrollment.key.json
  provisioner-password
EOF
fi

cat <<EOF

Public files to install into this repository:
  root_ca.crt
  root_ca.fingerprint
  device-enrollment.pub.json

Next online/offline CA exchange:
  1. Generate intermediate_ca.csr and intermediate_ca.key on the online CA host.
  2. Sign intermediate_ca.csr on the offline CA host.
  3. Install only the signed intermediate_ca.crt back onto the online CA host.

Next:
  $next_command
EOF
