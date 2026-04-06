{ lib, pdCa, runCommand }:
{
  name,
  approvedRootCommonName,
  approvedIntermediateCommonName,
  rogueRootCommonName,
  rogueIntermediateCommonName,
  serverCommonName,
  approvedClients ? [ ],
  rogueClients ? [ ],
  ccdAssignments ? { },
}:
runCommand "${name}-assets" { nativeBuildInputs = [ pdCa ]; } ''
  set -euo pipefail

  approved_dir="$out/approved"
  approved_root_dir="$approved_dir/root"
  approved_intermediate_dir="$approved_dir/intermediate"
  rogue_dir="$out/rogue"
  rogue_root_dir="$rogue_dir/root"
  rogue_intermediate_dir="$rogue_dir/intermediate"

  mkdir -p \
    "$approved_dir" \
    "$approved_root_dir" \
    "$approved_intermediate_dir" \
    "$rogue_dir" \
    "$rogue_root_dir" \
    "$rogue_intermediate_dir" \
    "$out/ccd"

  pd-ca init-root "$approved_root_dir" ${lib.escapeShellArg approvedRootCommonName}
  pd-ca issue-intermediate "$approved_root_dir" ${lib.escapeShellArg approvedIntermediateCommonName} "$approved_intermediate_dir"
  pd-ca init-root "$rogue_root_dir" ${lib.escapeShellArg rogueRootCommonName}
  pd-ca issue-intermediate "$rogue_root_dir" ${lib.escapeShellArg rogueIntermediateCommonName} "$rogue_intermediate_dir"

  pd-ca issue-leaf "$approved_intermediate_dir" openvpn-server server ${lib.escapeShellArg serverCommonName} "$approved_dir"

  ${lib.concatMapStringsSep "\n" (
    clientName:
    ''
      pd-ca issue-leaf "$approved_intermediate_dir" openvpn-client ${lib.escapeShellArg clientName} ${lib.escapeShellArg clientName} "$approved_dir"
    ''
  ) approvedClients}

  ${lib.concatMapStringsSep "\n" (
    clientName:
    ''
      pd-ca issue-leaf "$rogue_intermediate_dir" openvpn-client ${lib.escapeShellArg clientName} ${lib.escapeShellArg clientName} "$rogue_dir"
    ''
  ) rogueClients}

  cat "$approved_root_dir/ca.crt" "$approved_intermediate_dir/ca.crt" > "$approved_dir/ca.crt"
  cat "$approved_root_dir/ca.crt" > "$approved_dir/root-ca.crt"
  cat "$approved_intermediate_dir/ca.crt" > "$approved_dir/intermediate-ca.crt"

  cat "$rogue_root_dir/ca.crt" "$rogue_intermediate_dir/ca.crt" > "$rogue_dir/ca.crt"
  cat "$rogue_root_dir/ca.crt" > "$rogue_dir/root-ca.crt"
  cat "$rogue_intermediate_dir/ca.crt" > "$rogue_dir/intermediate-ca.crt"

  ${lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      clientName: vpnIp:
      ''
        cat > "$out/ccd/${clientName}" <<EOF
ifconfig-push ${vpnIp} 255.255.255.0
EOF
      ''
    ) ccdAssignments
  )}

  cat > "$out/tls-crypt.key" <<'EOF'
#
# 2048 bit OpenVPN static key
#
-----BEGIN OpenVPN Static key V1-----
553aabe853acdfe51cd6fcfea93dcbb0
c8797deadd1187606b1ea8f2315eb5e6
67c0d7e830f50df45686063b189d6c6b
aab8bb3430cc78f7bb1f78628d5c3742
0cef4f53a5acab2894905f4499f95d8e
e69b7b6748b17016f89e19e91481a9fd
bf8c10651f41a1d4fdf5f438925a6733
13cec8f04701eb47b8f7ffc48bc3d7af
65f07bce766015b87c3db4d668c655ff
be5a69522a8e60ccb217f8521681b45d
27c0b70bdfbfbb426c7646d80adf7482
3ddac58b25cb1c1bb100de974478b4c6
8b45a94261a2405e99810cb2b3abd49f
21b3198ada87ff3c4e656a008e540a8d
e7811584363597599cce2040a68ac00e
f2125540e0f7f4adc37cb3f0d922eeb7
-----END OpenVPN Static key V1-----
EOF

  rm -f \
    "$approved_root_dir/ca.srl" \
    "$approved_intermediate_dir/ca.srl" \
    "$rogue_root_dir/ca.srl" \
    "$rogue_intermediate_dir/ca.srl"
''
