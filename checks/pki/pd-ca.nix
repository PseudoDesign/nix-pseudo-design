{ pkgs, ... }:
pkgs.runCommand "pd-ca-check" { nativeBuildInputs = [ pkgs.gnugrep pkgs.openssl pkgs.pdCa ]; } ''
  set -euo pipefail

  workspace="$TMPDIR/pd-ca"
  root_dir="$workspace/authorities/root"
  intermediate_dir="$workspace/authorities/intermediate"
  server_dir="$workspace/issued/openvpn/servers/server"
  client_dir="$workspace/issued/openvpn/clients/client"
  bundle_file="$workspace/bundles/openvpn-ca.crt"

  pd-ca init-root-ca "$workspace" "pseudo.design Test Root CA"
  pd-ca init-intermediate-ca "$workspace" "pseudo.design Test Intermediate CA"
  pd-ca issue-openvpn-server "$workspace" server "pd-ca-test-server"
  pd-ca issue-openvpn-client "$workspace" client "pd-ca-test-client"

  openssl verify -CAfile "$bundle_file" "$server_dir/server.crt" | grep -F "$server_dir/server.crt: OK"
  openssl verify -CAfile "$bundle_file" "$client_dir/client.crt" | grep -F "$client_dir/client.crt: OK"

  openssl x509 -in "$intermediate_dir/ca.crt" -noout -text | grep -F "CA:TRUE, pathlen:0"
  openssl x509 -in "$server_dir/server.crt" -noout -text | grep -F "TLS Web Server Authentication"
  openssl x509 -in "$client_dir/client.crt" -noout -text | grep -F "TLS Web Client Authentication"

  test -f "$workspace/bundles/root-ca.crt"
  test -f "$workspace/bundles/intermediate-ca.crt"
  test -f "$server_dir/ca-chain.crt"
  test -f "$server_dir/full-chain.crt"
  test -f "$client_dir/ca-chain.crt"
  test -f "$client_dir/full-chain.crt"

  [ "$(ls -1 "$root_dir/issued/certs" | wc -l)" -eq 1 ]
  [ "$(ls -1 "$intermediate_dir/issued/certs" | wc -l)" -eq 2 ]
  grep -F "intermediate" "$root_dir/issued/index.txt"
  grep -F "server" "$intermediate_dir/issued/index.txt"
  grep -F "client" "$intermediate_dir/issued/index.txt"

  touch "$out"
''
