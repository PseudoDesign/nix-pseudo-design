{ pkgs, ... }:
pkgs.runCommand "pd-openvpn-identity-check" {
  nativeBuildInputs = [
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.openssl
    pkgs.pdCa
    pkgs.pdOpenvpnIdentity
  ];
} ''
  set -euo pipefail

  workspace="$TMPDIR/pd-openvpn-identity-ca"
  intermediate_dir="$workspace/authorities/intermediate"
  staged_server_dir="$TMPDIR/staged-server"
  staged_client_dir="$TMPDIR/staged-client"
  imported_server_identity_dir="$TMPDIR/imported-server"
  imported_identity_dir="$TMPDIR/imported-client"
  fresh_server_identity_dir="$TMPDIR/fresh-server"
  fresh_identity_dir="$TMPDIR/fresh-client"
  response_server_dir="$TMPDIR/response-server/server"
  response_dir="$TMPDIR/response-client/client"
  old_server_serial=""
  new_server_serial=""
  old_client_serial=""
  new_client_serial=""
  server_request_dir=""
  server_request_id=""
  request_dir=""
  request_id=""

  # Sign a pending identity request the same way the CA flow would.
  sign_identity_request() {
    local request_dir="$1"
    local response_dir="$2"
    local name="$3"
    local common_name="$4"
    local profile="$5"
    local extended_key_usage="$6"
    local ext_file="$TMPDIR/$name.ext"

    mkdir -p "$response_dir"
    cat > "$ext_file" <<EOF
basicConstraints=CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=$extended_key_usage
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EOF

    openssl x509 \
      -req \
      -sha256 \
      -days 3650 \
      -in "$request_dir/$name.csr" \
      -CA "$intermediate_dir/ca.crt" \
      -CAkey "$intermediate_dir/ca.key" \
      -CAserial "$intermediate_dir/serial" \
      -out "$response_dir/$name.crt" \
      -extfile "$ext_file" \
      >/dev/null 2>&1

    cp "$intermediate_dir/ca-chain.crt" "$response_dir/ca-chain.crt"
    cat "$response_dir/$name.crt" "$response_dir/ca-chain.crt" > "$response_dir/full-chain.crt"
    printf '%s\n' "$common_name" > "$response_dir/common-name"
    printf '%s\n' "$profile" > "$response_dir/profile"
  }

  # Prepare a CA workspace with one server and one client identity to import.
  pd-ca init-root-ca "$workspace" "pd-openvpn-identity Test Root CA"
  pd-ca init-intermediate-ca "$workspace" "pd-openvpn-identity Test Intermediate CA"
  pd-ca issue-openvpn-server "$workspace" server "pd-openvpn-identity-server"
  pd-ca issue-openvpn-client "$workspace" client "pd-openvpn-identity-client"
  pd-ca stage-openvpn-server "$workspace" server "$staged_server_dir"
  pd-ca stage-openvpn-client "$workspace" client "$staged_client_dir"

  # Import an existing issued key plus staged certificate bundle into local state.
  pd-openvpn-identity import-active \
    "$imported_server_identity_dir" \
    "$workspace/issued/openvpn/servers/server/server.key" \
    "$staged_server_dir/issued/openvpn/servers/server"

  pd-openvpn-identity import-active \
    "$imported_identity_dir" \
    "$workspace/issued/openvpn/clients/client/client.key" \
    "$staged_client_dir/issued/openvpn/clients/client"

  test -f "$imported_server_identity_dir/active/server.key"
  test -f "$imported_server_identity_dir/active/server.crt"
  [ "$(cat "$imported_server_identity_dir/identity-name")" = "server" ]
  [ "$(cat "$imported_server_identity_dir/profile")" = "openvpn-server" ]
  pd-openvpn-identity show "$imported_server_identity_dir" | grep -F "active: yes"

  test -f "$imported_identity_dir/active/client.key"
  test -f "$imported_identity_dir/active/client.crt"
  [ "$(cat "$imported_identity_dir/identity-name")" = "client" ]
  [ "$(cat "$imported_identity_dir/profile")" = "openvpn-client" ]
  pd-openvpn-identity show "$imported_identity_dir" | grep -F "active: yes"

  # New endpoints should be able to create an initial pending request locally.
  server_request_dir="$(pd-openvpn-identity init-server "$fresh_server_identity_dir" fresh-server "pd-openvpn-identity-fresh-server")"
  [ "$server_request_dir" = "$fresh_server_identity_dir/pending/initial" ]
  test -f "$fresh_server_identity_dir/pending/initial/fresh-server.key"
  test -f "$fresh_server_identity_dir/pending/initial/fresh-server.csr"
  pd-openvpn-identity show "$fresh_server_identity_dir" | grep -F "pending: initial"

  request_dir="$(pd-openvpn-identity init-client "$fresh_identity_dir" fresh "pd-openvpn-identity-fresh")"
  [ "$request_dir" = "$fresh_identity_dir/pending/initial" ]
  test -f "$fresh_identity_dir/pending/initial/fresh.key"
  test -f "$fresh_identity_dir/pending/initial/fresh.csr"
  pd-openvpn-identity show "$fresh_identity_dir" | grep -F "pending: initial"

  # Rekey the imported server identity and confirm the old active tree is archived.
  old_server_serial="$(openssl x509 -in "$imported_server_identity_dir/active/server.crt" -noout -serial | cut -d= -f2)"
  server_request_dir="$(pd-openvpn-identity prepare-server-rekey "$imported_server_identity_dir" server "pd-openvpn-identity-server")"
  server_request_id="''${server_request_dir##*/}"

  sign_identity_request \
    "$server_request_dir" \
    "$response_server_dir" \
    server \
    "pd-openvpn-identity-server" \
    openvpn-server \
    serverAuth

  pd-openvpn-identity activate-pending "$imported_server_identity_dir" "$server_request_id" "$response_server_dir"

  new_server_serial="$(openssl x509 -in "$imported_server_identity_dir/active/server.crt" -noout -serial | cut -d= -f2)"
  [ "$old_server_serial" != "$new_server_serial" ]
  [ "$(cat "$imported_server_identity_dir/active/installed-request-id")" = "$server_request_id" ]
  [ ! -e "$server_request_dir" ]

  set -- "$imported_server_identity_dir/history"/*
  [ "$#" -eq 1 ]
  [ -d "$1" ]
  test -f "$1/server.key"
  test -f "$1/server.crt"

  # Rekey the imported client identity and archive the previous active version.
  old_client_serial="$(openssl x509 -in "$imported_identity_dir/active/client.crt" -noout -serial | cut -d= -f2)"
  request_dir="$(pd-openvpn-identity prepare-client-rekey "$imported_identity_dir" client "pd-openvpn-identity-client")"
  request_id="''${request_dir##*/}"

  sign_identity_request \
    "$request_dir" \
    "$response_dir" \
    client \
    "pd-openvpn-identity-client" \
    openvpn-client \
    clientAuth

  pd-openvpn-identity activate-pending "$imported_identity_dir" "$request_id" "$response_dir"

  new_client_serial="$(openssl x509 -in "$imported_identity_dir/active/client.crt" -noout -serial | cut -d= -f2)"
  [ "$old_client_serial" != "$new_client_serial" ]
  [ "$(cat "$imported_identity_dir/active/installed-request-id")" = "$request_id" ]
  [ ! -e "$request_dir" ]

  set -- "$imported_identity_dir/history"/*
  [ "$#" -eq 1 ]
  [ -d "$1" ]
  test -f "$1/client.key"
  test -f "$1/client.crt"

  touch "$out"
''
