{ pkgs, ... }:
pkgs.runCommand "pd-openvpn-install-pki-check" {
  nativeBuildInputs = [
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.openssl
    pkgs.pdCa
    pkgs.pdOpenvpnInstallPki
  ];
} ''
  set -euo pipefail

  workspace="$TMPDIR/pd-openvpn-install-pki"
  staged_server_dir="$TMPDIR/staged-server"
  staged_client_dir="$TMPDIR/staged-client"
  installed_server_dir="$TMPDIR/installed-server"
  installed_dir="$TMPDIR/installed-client"
  legacy_staged_server_dir="$TMPDIR/legacy-staged-server"
  legacy_staged_dir="$TMPDIR/legacy-staged-client"
  server_dir="$workspace/issued/openvpn/servers/server"
  other_server_dir="$workspace/issued/openvpn/servers/other"
  client_dir="$workspace/issued/openvpn/clients/client"
  other_client_dir="$workspace/issued/openvpn/clients/other"
  installed_server_identity_dir="$installed_server_dir/issued/openvpn/servers/server"
  installed_identity_dir="$installed_dir/issued/openvpn/clients/client"

  # Produce staged public trees plus separate private keys for both roles.
  pd-ca init-root-ca "$workspace" "pd-openvpn-install-pki Test Root CA"
  pd-ca init-intermediate-ca "$workspace" "pd-openvpn-install-pki Test Intermediate CA"
  pd-ca issue-openvpn-server "$workspace" server "pd-openvpn-install-server"
  pd-ca issue-openvpn-server "$workspace" other "pd-openvpn-install-other-server"
  pd-ca issue-openvpn-client "$workspace" client "pd-openvpn-install-client"
  pd-ca issue-openvpn-client "$workspace" other "pd-openvpn-install-other"
  pd-ca stage-openvpn-server "$workspace" server "$staged_server_dir"
  pd-ca stage-openvpn-client "$workspace" client "$staged_client_dir"

  printf '%s\n' "test tls crypt key" > "$TMPDIR/tls-crypt.key"

  # Install a server staged tree with its private key injected at install time.
  pd-openvpn-install-pki \
    "$staged_server_dir" \
    "$installed_server_dir" \
    "$server_dir/server.key" \
    "$TMPDIR/tls-crypt.key"

  # Install a client staged tree with the same split public/private layout.
  pd-openvpn-install-pki \
    "$staged_client_dir" \
    "$installed_dir" \
    "$client_dir/client.key" \
    "$TMPDIR/tls-crypt.key"

  # Successful installs should restore a usable runtime tree without mutating stage.
  test -f "$installed_server_identity_dir/server.key"
  test -f "$installed_server_identity_dir/server.crt"
  test -f "$installed_server_dir/tls-crypt.key"
  [ "$(stat -c '%a' "$installed_server_identity_dir/server.key")" = "600" ]
  openssl verify -CAfile "$installed_server_dir/bundles/openvpn-ca.crt" "$installed_server_identity_dir/server.crt" | grep -F "$installed_server_identity_dir/server.crt: OK"
  test ! -f "$staged_server_dir/issued/openvpn/servers/server/server.key"

  test -f "$installed_identity_dir/client.key"
  test -f "$installed_identity_dir/client.crt"
  test -f "$installed_dir/tls-crypt.key"
  [ "$(stat -c '%a' "$installed_identity_dir/client.key")" = "600" ]
  openssl verify -CAfile "$installed_dir/bundles/openvpn-ca.crt" "$installed_identity_dir/client.crt" | grep -F "$installed_identity_dir/client.crt: OK"
  test ! -f "$staged_client_dir/issued/openvpn/clients/client/client.key"

  # Reject installs where the supplied key does not match the staged certificate.
  ! pd-openvpn-install-pki \
    "$staged_server_dir" \
    "$TMPDIR/mismatch-server-install" \
    "$other_server_dir/other.key" \
    >"$TMPDIR/mismatch-server.log" 2>&1
  grep -F "Identity key source does not match staged certificate" "$TMPDIR/mismatch-server.log"

  ! pd-openvpn-install-pki \
    "$staged_client_dir" \
    "$TMPDIR/mismatch-install" \
    "$other_client_dir/other.key" \
    >"$TMPDIR/mismatch.log" 2>&1
  grep -F "Identity key source does not match staged certificate" "$TMPDIR/mismatch.log"

  # Reject legacy staged trees that still embed a private key.
  cp -R "$staged_server_dir" "$legacy_staged_server_dir"
  cp "$server_dir/server.key" "$legacy_staged_server_dir/issued/openvpn/servers/server/server.key"

  ! pd-openvpn-install-pki \
    "$legacy_staged_server_dir" \
    "$TMPDIR/legacy-server-install" \
    "$server_dir/server.key" \
    >"$TMPDIR/legacy-server.log" 2>&1
  grep -F "Staged PKI source must not contain an identity private key" "$TMPDIR/legacy-server.log"

  cp -R "$staged_client_dir" "$legacy_staged_dir"
  cp "$client_dir/client.key" "$legacy_staged_dir/issued/openvpn/clients/client/client.key"

  ! pd-openvpn-install-pki \
    "$legacy_staged_dir" \
    "$TMPDIR/legacy-install" \
    "$client_dir/client.key" \
    >"$TMPDIR/legacy.log" 2>&1
  grep -F "Staged PKI source must not contain an identity private key" "$TMPDIR/legacy.log"

  touch "$out"
''
