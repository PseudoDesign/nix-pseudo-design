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
  staged_server_dir="$TMPDIR/staged-server"
  staged_client_dir="$TMPDIR/staged-client"
  server_history_root="$workspace/history/openvpn/servers/server"
  client_history_root="$workspace/history/openvpn/clients/client"
  old_server_serial=""
  old_client_serial=""
  new_server_serial=""
  new_client_serial=""
  archived_server_dir=""
  archived_client_dir=""

  # Build a CA workspace and issue one server plus one client identity.
  pd-ca init-root-ca "$workspace" "pseudo.design Test Root CA"
  pd-ca init-intermediate-ca "$workspace" "pseudo.design Test Intermediate CA"
  pd-ca issue-openvpn-server "$workspace" server "pd-ca-test-server"
  pd-ca issue-openvpn-client "$workspace" client "pd-ca-test-client"

  # Renew the server in place and rotate the client through revocation/history.
  old_server_serial="$(openssl x509 -in "$server_dir/server.crt" -noout -serial | cut -d= -f2)"
  old_client_serial="$(openssl x509 -in "$client_dir/client.crt" -noout -serial | cut -d= -f2)"
  pd-ca renew-openvpn-server "$workspace" server
  pd-ca rotate-openvpn-client "$workspace" client
  new_server_serial="$(openssl x509 -in "$server_dir/server.crt" -noout -serial | cut -d= -f2)"
  new_client_serial="$(openssl x509 -in "$client_dir/client.crt" -noout -serial | cut -d= -f2)"
  [ "$old_server_serial" != "$new_server_serial" ]
  [ "$old_client_serial" != "$new_client_serial" ]
  [ "$(cat "$server_dir/common-name")" = "pd-ca-test-server" ]
  [ "$(cat "$client_dir/common-name")" = "pd-ca-test-client" ]

  # Capture the archived identities created by renew/rotate.
  set -- "$server_history_root"/*
  [ "$#" -eq 1 ]
  [ -d "$1" ]
  archived_server_dir="$1"

  set -- "$client_history_root"/*
  [ "$#" -eq 1 ]
  [ -d "$1" ]
  archived_client_dir="$1"

  # Stage public-consumer trees for the server and client outputs.
  pd-ca stage-openvpn-server "$workspace" server "$staged_server_dir"
  pd-ca stage-openvpn-client "$workspace" client "$staged_client_dir"

  # Verify trust and revocation behavior for current, archived, and staged certs.
  openssl verify -CAfile "$bundle_file" "$server_dir/server.crt" | grep -F "$server_dir/server.crt: OK"
  openssl verify -CAfile "$bundle_file" "$archived_server_dir/server.crt" | grep -F "$archived_server_dir/server.crt: OK"
  openssl verify -crl_check -CAfile "$bundle_file" -CRLfile "$crl_file" "$client_dir/client.crt" | grep -F "$client_dir/client.crt: OK"
  ! openssl verify -crl_check -CAfile "$bundle_file" -CRLfile "$crl_file" "$archived_client_dir/client.crt" >"$TMPDIR/client-verify.log" 2>&1
  grep -F "certificate revoked" "$TMPDIR/client-verify.log"
  openssl verify -CAfile "$staged_server_dir/bundles/openvpn-ca.crt" "$staged_server_dir/issued/openvpn/servers/server/server.crt" | grep -F "$staged_server_dir/issued/openvpn/servers/server/server.crt: OK"
  openssl verify -crl_check -CAfile "$staged_client_dir/bundles/openvpn-ca.crt" -CRLfile "$staged_client_dir/bundles/openvpn-ca.crl.pem" "$staged_client_dir/issued/openvpn/clients/client/client.crt" | grep -F "$staged_client_dir/issued/openvpn/clients/client/client.crt: OK"

  # Check that the generated X.509 extensions match the intended roles.
  openssl x509 -in "$intermediate_dir/ca.crt" -noout -text | grep -F "CA:TRUE, pathlen:0"
  openssl x509 -in "$server_dir/server.crt" -noout -text | grep -F "TLS Web Server Authentication"
  openssl x509 -in "$client_dir/client.crt" -noout -text | grep -F "TLS Web Client Authentication"

  # The CA workspace keeps private keys, while staged trees stay public-only.
  test -f "$workspace/bundles/root-ca.crt"
  test -f "$workspace/bundles/intermediate-ca.crt"
  test -f "$crl_file"
  test -f "$server_dir/ca-chain.crt"
  test -f "$server_dir/full-chain.crt"
  test -f "$client_dir/ca-chain.crt"
  test -f "$client_dir/full-chain.crt"
  test -f "$staged_server_dir/bundles/openvpn-ca.crl.pem"
  test ! -f "$staged_server_dir/issued/openvpn/servers/server/server.key"
  test ! -f "$staged_client_dir/issued/openvpn/clients/client/client.key"
  test -f "$archived_server_dir/server.key"
  test -f "$archived_client_dir/client.key"

  # Issuance and revocation records should reflect the operations above.
  [ "$(ls -1 "$root_dir/issued/certs" | wc -l)" -eq 1 ]
  [ "$(ls -1 "$intermediate_dir/issued/certs" | wc -l)" -eq 4 ]
  [ "$(ls -1 "$intermediate_dir/revoked/certs" | wc -l)" -eq 1 ]
  grep -F "intermediate" "$root_dir/issued/records.tsv"
  grep -F "server" "$intermediate_dir/issued/records.tsv"
  grep -F "client" "$intermediate_dir/issued/records.tsv"
  grep -F "client" "$intermediate_dir/revoked/records.tsv"

  touch "$out"
''
