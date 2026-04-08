{ pkgs, ... }:
pkgs.runCommand "pd-openvpn-generate-tls-crypt-key-check" { nativeBuildInputs = [ pkgs.coreutils pkgs.gnugrep pkgs.pdOpenvpnGenerateTlsCryptKey ]; } ''
  set -euo pipefail

  key_file="$TMPDIR/tls-crypt.key"

  # Generate a fresh key and verify the expected file mode and framing.
  pd-openvpn-generate-tls-crypt-key "$key_file"
  test -f "$key_file"
  [ "$(stat -c '%a' "$key_file")" = "600" ]
  grep -F "BEGIN OpenVPN Static key V1" "$key_file"
  grep -F "END OpenVPN Static key V1" "$key_file"

  # Reusing the same path without --force should fail loudly.
  ! pd-openvpn-generate-tls-crypt-key "$key_file" >"$TMPDIR/reuse.log" 2>&1
  grep -F "Refusing to overwrite existing tls-crypt key" "$TMPDIR/reuse.log"

  # Forced regeneration should overwrite the file with another valid key.
  pd-openvpn-generate-tls-crypt-key --force "$key_file"
  grep -F "BEGIN OpenVPN Static key V1" "$key_file"

  touch "$out"
''
