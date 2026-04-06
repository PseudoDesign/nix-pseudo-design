{ pkgs, ... }:
pkgs.runCommand "pd-ca-check" { nativeBuildInputs = [ pkgs.gnugrep pkgs.openssl pkgs.pdCa ]; } ''
  set -euo pipefail

  work_dir="$TMPDIR/pd-ca"
  root_dir="$work_dir/root"
  intermediate_dir="$work_dir/intermediate"
  issued_dir="$work_dir/issued"
  bundle_file="$work_dir/ca-bundle.crt"

  mkdir -p "$root_dir" "$intermediate_dir" "$issued_dir"

  pd-ca init-root "$root_dir" "pseudo.design Test Root CA"
  pd-ca issue-intermediate "$root_dir" "pseudo.design Test Intermediate CA" "$intermediate_dir"
  pd-ca issue-leaf "$intermediate_dir" openvpn-server server "pd-ca-test-server" "$issued_dir"
  pd-ca issue-leaf "$intermediate_dir" openvpn-client client "pd-ca-test-client" "$issued_dir"

  cat "$root_dir/ca.crt" "$intermediate_dir/ca.crt" > "$bundle_file"

  openssl verify -CAfile "$bundle_file" "$issued_dir/server.crt" | grep -F "$issued_dir/server.crt: OK"
  openssl verify -CAfile "$bundle_file" "$issued_dir/client.crt" | grep -F "$issued_dir/client.crt: OK"

  openssl x509 -in "$intermediate_dir/ca.crt" -noout -text | grep -F "CA:TRUE, pathlen:0"
  openssl x509 -in "$issued_dir/server.crt" -noout -text | grep -F "TLS Web Server Authentication"
  openssl x509 -in "$issued_dir/client.crt" -noout -text | grep -F "TLS Web Client Authentication"

  touch "$out"
''
