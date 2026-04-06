{ testers, pkgs, ... }:
let
  testAssets = pkgs.runCommand "openvpn-wrong-ca-assets" { nativeBuildInputs = [ pkgs.openssl ]; } ''
    set -euo pipefail

    make_ca() {
      local out_dir="$1"
      local common_name="$2"

      mkdir -p "$out_dir"

      cat > "$out_dir/ca.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3_ca
prompt = no

[dn]
CN = $common_name

[v3_ca]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
EOF

      openssl req \
        -x509 \
        -newkey rsa:2048 \
        -sha256 \
        -days 3650 \
        -nodes \
        -config "$out_dir/ca.cnf" \
        -keyout "$out_dir/ca.key" \
        -out "$out_dir/ca.crt" \
        >/dev/null 2>&1
    }

    make_leaf() {
      local ca_dir="$1"
      local name="$2"
      local common_name="$3"
      local extended_key_usage="$4"
      local out_dir="$5"

      cat > "$out_dir/$name.cnf" <<EOF
[req]
distinguished_name = dn
req_extensions = v3_req
prompt = no

[dn]
CN = $common_name

[v3_req]
basicConstraints = CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = $extended_key_usage
subjectKeyIdentifier = hash
EOF

      openssl req \
        -new \
        -newkey rsa:2048 \
        -nodes \
        -config "$out_dir/$name.cnf" \
        -keyout "$out_dir/$name.key" \
        -out "$out_dir/$name.csr" \
        >/dev/null 2>&1

      cat > "$out_dir/$name.ext" <<EOF
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
        -in "$out_dir/$name.csr" \
        -CA "$ca_dir/ca.crt" \
        -CAkey "$ca_dir/ca.key" \
        -CAcreateserial \
        -out "$out_dir/$name.crt" \
        -extfile "$out_dir/$name.ext" \
        >/dev/null 2>&1

      rm \
        "$out_dir/$name.cnf" \
        "$out_dir/$name.csr" \
        "$out_dir/$name.ext"
    }

    approved_dir="$out/approved"
    rogue_dir="$out/rogue"

    mkdir -p "$approved_dir" "$rogue_dir" "$out/ccd"

    make_ca "$approved_dir" "OpenVPN Wrong-CA Approved CA"
    make_ca "$rogue_dir" "OpenVPN Wrong-CA Rogue CA"

    make_leaf "$approved_dir" "server" "openvpn-wrong-ca-server" "serverAuth" "$approved_dir"
    make_leaf "$approved_dir" "approved" "approved" "clientAuth" "$approved_dir"
    # Reuse the same tls-crypt key to isolate certificate-authority admission checks.
    make_leaf "$rogue_dir" "rogue" "rogue" "clientAuth" "$rogue_dir"

    cat > "$out/ccd/approved" <<EOF
ifconfig-push 10.9.0.10 255.255.255.0
EOF

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

    rm \
      "$approved_dir/ca.cnf" \
      "$approved_dir/ca.key" \
      "$approved_dir/ca.srl" \
      "$rogue_dir/ca.cnf" \
      "$rogue_dir/ca.key" \
      "$rogue_dir/ca.srl"
  '';

  serverIp = "192.168.2.1";
  instanceName = "wrong-ca";
  vpnSubnet = "10.9.0.0";
  approvedVpnIp = "10.9.0.10";
  statusFile = "/run/openvpn-wrong-ca/status.log";

  mkExternalInterface =
    address:
    {
      useDHCP = false;
      ipv4.addresses = [
        {
          inherit address;
          prefixLength = 24;
        }
      ];
    };

  mkClientNode =
    {
      hostName,
      externalIp,
      certDir,
      certName,
    }:
    { ... }:
    {
      imports = [ ../modules/pd-openvpn-client.nix ];

      networking.hostName = hostName;
      networking.useDHCP = false;
      networking.firewall.enable = false;
      networking.interfaces.eth1 = mkExternalInterface externalIp;
      virtualisation.interfaces.eth1 = {
        vlan = 1;
        assignIP = false;
      };

      services.pdOpenvpnClient = {
        enable = true;
        inherit instanceName;
        remoteHost = serverIp;
        caCertFile = "${certDir}/ca.crt";
        clientCertFile = "${certDir}/${certName}.crt";
        clientKeyFile = "${certDir}/${certName}.key";
        tlsCryptKeyFile = "${testAssets}/tls-crypt.key";
        verifyX509Name = "openvpn-wrong-ca-server";
      };

      system.stateVersion = "25.11";
    };
in
testers.runNixOSTest {
  name = "openvpn-wrong-ca";

  nodes = {
    # The VPN gateway trusts only the approved CA and should reject rogue clients.
    gateway =
      { ... }:
      {
        imports = [ ../modules/pd-openvpn-server.nix ];

        networking.hostName = "gateway";
        networking.useDHCP = false;
        networking.interfaces.eth1 = mkExternalInterface serverIp;
        virtualisation.interfaces.eth1 = {
          vlan = 1;
          assignIP = false;
        };

        services.pdOpenvpnServer = {
          enable = true;
          inherit instanceName;
          runtimeDir = "/run/openvpn-wrong-ca";
          inherit vpnSubnet;
          caCertFile = "${testAssets}/approved/ca.crt";
          serverCertFile = "${testAssets}/approved/server.crt";
          serverKeyFile = "${testAssets}/approved/server.key";
          tlsCryptKeyFile = "${testAssets}/tls-crypt.key";
          clientConfigDir = "${testAssets}/ccd";
        };

        system.stateVersion = "25.11";
      };

    # Approved client proves the server is working while the rogue client is denied.
    approved = mkClientNode {
      hostName = "approved";
      externalIp = "192.168.2.2";
      certDir = "${testAssets}/approved";
      certName = "approved";
    };

    # Rogue client uses the wrong CA and should never receive a tunnel interface.
    rogue = mkClientNode {
      hostName = "rogue";
      externalIp = "192.168.2.3";
      certDir = "${testAssets}/rogue";
      certName = "rogue";
    };
  };

  testScript = ''
    start_all()

    gateway.wait_for_unit("openvpn-wrong-ca.service")
    approved.wait_for_unit("openvpn-wrong-ca.service")
    rogue.wait_for_unit("openvpn-wrong-ca.service")

    gateway.wait_until_succeeds("grep -F 'CLIENT_LIST,approved,' ${statusFile}")
    approved.wait_until_succeeds("ping -c 1 10.9.0.1")
    gateway.wait_until_succeeds("ping -c 1 ${approvedVpnIp}")

    rogue.succeed("sleep 5")
    rogue.fail("ip -o -4 addr show dev tun0 | grep -F '10.9.0.'")
    gateway.fail("grep -F 'CLIENT_LIST,rogue,' ${statusFile}")
  '';
}
