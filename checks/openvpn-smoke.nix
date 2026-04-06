{ testers, pkgs, ... }:
let
  testAssets = pkgs.runCommand "openvpn-smoke-assets" { nativeBuildInputs = [ pkgs.openssl ]; } ''
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

    make_ca "$approved_dir" "OpenVPN Smoke Approved CA"
    make_ca "$rogue_dir" "OpenVPN Smoke Rogue CA"

    make_leaf "$approved_dir" "server" "openvpn-smoke-server" "serverAuth" "$approved_dir"
    make_leaf "$approved_dir" "client1" "client1" "clientAuth" "$approved_dir"
    make_leaf "$approved_dir" "client2" "client2" "clientAuth" "$approved_dir"
    # Reuse the same tls-crypt key to isolate certificate-authority admission checks.
    make_leaf "$rogue_dir" "rogue" "rogue" "clientAuth" "$rogue_dir"

    cat > "$out/ccd/client1" <<EOF
ifconfig-push 10.8.0.10 255.255.255.0
EOF

    cat > "$out/ccd/client2" <<EOF
ifconfig-push 10.8.0.11 255.255.255.0
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

  serverIp = "192.168.1.1";

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
      networking.hostName = hostName;
      networking.useDHCP = false;
      networking.firewall.enable = false;
      networking.interfaces.eth1 = mkExternalInterface externalIp;
      virtualisation.interfaces.eth1 = {
        vlan = 1;
        assignIP = false;
      };

      services.openvpn.servers.smoke = {
        config = ''
          client
          dev tun
          proto udp
          remote ${serverIp} 1194
          nobind
          tls-client
          persist-key
          persist-tun
          data-ciphers AES-256-GCM:AES-128-GCM
          tls-version-min 1.2
          ca ${certDir}/ca.crt
          cert ${certDir}/${certName}.crt
          key ${certDir}/${certName}.key
          tls-crypt ${testAssets}/tls-crypt.key
          remote-cert-tls server
          verb 3
        '';
      };

      system.stateVersion = "25.11";
    };
in
testers.runNixOSTest {
  name = "openvpn-smoke";

  nodes = {
    # The VPN gateway accepts only clients signed by the approved test CA.
    gateway =
      { ... }:
      {
        networking.hostName = "gateway";
        networking.useDHCP = false;
        networking.firewall.allowedUDPPorts = [ 1194 ];
        networking.interfaces.eth1 = mkExternalInterface serverIp;
        virtualisation.interfaces.eth1 = {
          vlan = 1;
          assignIP = false;
        };

        systemd.tmpfiles.rules = [ "d /run/openvpn-smoke 0755 root root -" ];

        services.openvpn.servers.smoke = {
          config = ''
            port 1194
            proto udp
            dev tun0
            topology subnet
            server 10.8.0.0 255.255.255.0
            tls-server
            keepalive 10 60
            persist-key
            persist-tun
            data-ciphers AES-256-GCM:AES-128-GCM
            tls-version-min 1.2
            dh none
            ca ${testAssets}/approved/ca.crt
            cert ${testAssets}/approved/server.crt
            key ${testAssets}/approved/server.key
            tls-crypt ${testAssets}/tls-crypt.key
            verify-client-cert require
            client-config-dir ${testAssets}/ccd
            ifconfig-pool-persist /run/openvpn-smoke/ipp.txt
            status /run/openvpn-smoke/status.log
            status-version 2
            verb 3
          '';
        };

        system.stateVersion = "25.11";
      };

    # Approved client with its own certificate and a fixed tunnel address.
    client1 = mkClientNode {
      hostName = "client1";
      externalIp = "192.168.1.2";
      certDir = "${testAssets}/approved";
      certName = "client1";
    };

    # Second approved client used to prove multiple trusted clients can connect.
    client2 = mkClientNode {
      hostName = "client2";
      externalIp = "192.168.1.3";
      certDir = "${testAssets}/approved";
      certName = "client2";
    };

    # Unapproved client signed by a different CA; it should never join the VPN.
    rogue = mkClientNode {
      hostName = "rogue";
      externalIp = "192.168.1.4";
      certDir = "${testAssets}/rogue";
      certName = "rogue";
    };
  };

  testScript = ''
    start_all()

    gateway.wait_for_unit("openvpn-smoke.service")
    client1.wait_for_unit("openvpn-smoke.service")
    client2.wait_for_unit("openvpn-smoke.service")
    rogue.wait_for_unit("openvpn-smoke.service")

    gateway.wait_until_succeeds("grep -F 'CLIENT_LIST,client1,' /run/openvpn-smoke/status.log")
    gateway.wait_until_succeeds("grep -F 'CLIENT_LIST,client2,' /run/openvpn-smoke/status.log")

    client1.wait_until_succeeds("ping -c 1 10.8.0.1")
    client2.wait_until_succeeds("ping -c 1 10.8.0.1")
    gateway.wait_until_succeeds("ping -c 1 10.8.0.10")
    gateway.wait_until_succeeds("ping -c 1 10.8.0.11")

    rogue.succeed("sleep 5")
    rogue.fail("ip -o -4 addr show dev tun0 | grep -F '10.8.0.'")
    gateway.fail("grep -F 'CLIENT_LIST,rogue,' /run/openvpn-smoke/status.log")
  '';
}
