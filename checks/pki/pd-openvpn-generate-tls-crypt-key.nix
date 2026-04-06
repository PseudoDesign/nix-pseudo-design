{ pkgs, ... }:
pkgs.runCommand "pd-openvpn-generate-tls-crypt-key-check" { nativeBuildInputs = [ pkgs.coreutils pkgs.gnugrep pkgs.pdOpenvpnGenerateTlsCryptKey ]; } ''
  set -euo pipefail

  key_file="$TMPDIR/tls-crypt.key"

  pd-openvpn-generate-tls-crypt-key "$key_file"
  test -f "$key_file"
  [ "$(stat -c '%a' "$key_file")" = "600" ]
  grep -F "BEGIN OpenVPN Static key V1" "$key_file"
  grep -F "END OpenVPN Static key V1" "$key_file"

  ! pd-openvpn-generate-tls-crypt-key "$key_file" >"$TMPDIR/reuse.log" 2>&1
  grep -F "Refusing to overwrite existing tls-crypt key" "$TMPDIR/reuse.log"

  pd-openvpn-generate-tls-crypt-key --force "$key_file"
  grep -F "BEGIN OpenVPN Static key V1" "$key_file"

  touch "$out"
''
