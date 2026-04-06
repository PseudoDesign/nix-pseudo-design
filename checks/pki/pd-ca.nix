{ pkgs, ... }:
pkgs.runCommand "pd-ca-check" { nativeBuildInputs = [ pkgs.gnugrep pkgs.openssl pkgs.pdCa ]; } ''
  set -euo pipefail

  workspace="$TMPDIR/pd-ca"
  root_dir="$workspace/authorities/root"
  intermediate_dir="$workspace/authorities/intermediate"
  server_dir="$workspace/issued/openvpn/servers/server"
  client_dir="$workspace/issued/openvpn/clients/client"
  bundle_file="$workspace/bundles/openvpn-ca.crt"
  crl_file="$workspace/bundles/openvpn-ca.crl.pem"

  pd-ca init-root-ca "$workspace" "pseudo.design Test Root CA"
  pd-ca init-intermediate-ca "$workspace" "pseudo.design Test Intermediate CA"
  pd-ca issue-openvpn-server "$workspace" server "pd-ca-test-server"
  pd-ca issue-openvpn-client "$workspace" client "pd-ca-test-client"
  pd-ca revoke-openvpn-client "$workspace" client

  openssl verify -CAfile "$bundle_file" "$server_dir/server.crt" | grep -F "$server_dir/server.crt: OK"
  ! openssl verify -crl_check -CAfile "$bundle_file" -CRLfile "$crl_file" "$client_dir/client.crt" >"$TMPDIR/client-verify.log" 2>&1
  grep -F "certificate revoked" "$TMPDIR/client-verify.log"

  openssl x509 -in "$intermediate_dir/ca.crt" -noout -text | grep -F "CA:TRUE, pathlen:0"
  openssl x509 -in "$server_dir/server.crt" -noout -text | grep -F "TLS Web Server Authentication"
  openssl x509 -in "$client_dir/client.crt" -noout -text | grep -F "TLS Web Client Authentication"

  test -f "$workspace/bundles/root-ca.crt"
  test -f "$workspace/bundles/intermediate-ca.crt"
  test -f "$crl_file"
  test -f "$server_dir/ca-chain.crt"
  test -f "$server_dir/full-chain.crt"
  test -f "$client_dir/ca-chain.crt"
  test -f "$client_dir/full-chain.crt"

  [ "$(ls -1 "$root_dir/issued/certs" | wc -l)" -eq 1 ]
  [ "$(ls -1 "$intermediate_dir/issued/certs" | wc -l)" -eq 2 ]
  [ "$(ls -1 "$intermediate_dir/revoked/certs" | wc -l)" -eq 1 ]
  grep -F "intermediate" "$root_dir/issued/records.tsv"
  grep -F "server" "$intermediate_dir/issued/records.tsv"
  grep -F "client" "$intermediate_dir/issued/records.tsv"
  grep -F "client" "$intermediate_dir/revoked/records.tsv"

  touch "$out"
''
