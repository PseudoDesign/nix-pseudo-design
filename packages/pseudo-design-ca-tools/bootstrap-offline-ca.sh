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

Create the pseudo.design root CA, online intermediate CA, and device enrollment
JWK provisioner in CA_DIR. CA_DIR must be outside this repository.

The script is idempotent: existing complete artifacts are kept.
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

create_password_file "$ca_dir/root-password"
create_password_file "$ca_dir/intermediate-password"
create_password_file "$ca_dir/provisioner-password"

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

if ensure_complete_pair "$ca_dir/intermediate_ca.crt" "$ca_dir/intermediate_ca.key"; then
  printf 'Keeping existing intermediate CA: %s\n' "$ca_dir/intermediate_ca.crt"
else
  step certificate create \
    "$PSEUDO_DESIGN_CA_INTERMEDIATE_NAME" \
    "$ca_dir/intermediate_ca.crt" \
    "$ca_dir/intermediate_ca.key" \
    --profile intermediate-ca \
    --ca "$ca_dir/root_ca.crt" \
    --ca-key "$ca_dir/root_ca.key" \
    --ca-password-file "$ca_dir/root-password" \
    --password-file "$ca_dir/intermediate-password" \
    --kty "$PSEUDO_DESIGN_CA_KEY_TYPE" \
    --curve "$PSEUDO_DESIGN_CA_CURVE"
  chmod 0644 "$ca_dir/intermediate_ca.crt"
  chmod 0600 "$ca_dir/intermediate_ca.key"
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
  root_ca.key
  root-password
  device-enrollment.key.json
  provisioner-password

Online CA files to stage onto mako:
  root_ca.crt
  intermediate_ca.crt
  intermediate_ca.key
  intermediate-password

Public files to install into this repository:
  root_ca.crt
  root_ca.fingerprint
  device-enrollment.pub.json

Next:
  $next_command
EOF
