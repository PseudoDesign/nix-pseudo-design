{ testers, pkgs, ... }:
let
  lib = pkgs.lib;
  mkOpenvpnTestAssets = pkgs.callPackage ./lib/test-assets.nix { };
  testAssets = mkOpenvpnTestAssets {
    name = "openvpn-smoke";
    approvedRootCommonName = "OpenVPN Smoke Approved Root CA";
    approvedIntermediateCommonName = "OpenVPN Smoke Approved Intermediate CA";
    rogueRootCommonName = "OpenVPN Smoke Rogue Root CA";
    rogueIntermediateCommonName = "OpenVPN Smoke Rogue Intermediate CA";
    serverCommonName = "openvpn-smoke-server";
    approvedClients = [
      "client1"
      "client2"
    ];
    rogueClients = [ "rogue" ];
    ccdAssignments = {
      client1 = "10.8.0.10";
      client2 = "10.8.0.11";
    };
  };

  serverIp = "192.168.1.1";
  approvedServerStageDir = "${testAssets}/staged/approved/server";
  approvedBundleDir = "${approvedServerStageDir}/bundles";
  rogueIdentityDir = "${testAssets}/staged/rogue/clients/rogue/issued/openvpn/clients/rogue";
  client1VpnIp = "10.8.0.10";
  client2VpnIp = "10.8.0.11";

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
      identityDir,
      bundleDir,
      installSourceDir ? null,
      installTlsCryptSourceFile ? null,
    }:
    { ... }:
    {
      imports = [ ../../modules/openvpn/client.nix ];

      networking.hostName = hostName;
      networking.useDHCP = false;
      networking.firewall.enable = false;
      networking.interfaces.eth1 = mkExternalInterface externalIp;
      virtualisation.interfaces.eth1 = {
        vlan = 1;
        assignIP = false;
      };

      services.pdOpenvpnClient =
        {
          enable = true;
          instanceName = "smoke";
          remoteHost = serverIp;
          pki =
            {
              install =
                {
                  sourceDir = installSourceDir;
                }
                // lib.optionalAttrs (installTlsCryptSourceFile != null) {
                  tlsCryptSourceFile = installTlsCryptSourceFile;
                };
            }
            // lib.optionalAttrs (bundleDir != null) {
              bundleDir = bundleDir;
            }
            // lib.optionalAttrs (identityDir != null) {
              identityDir = identityDir;
            };
          verifyX509Name = "openvpn-smoke-server";
        }
        // lib.optionalAttrs (installTlsCryptSourceFile == null) {
          tlsCryptKeyFile = "${testAssets}/tls-crypt.key";
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
        imports = [ ../../modules/openvpn/server.nix ];

        networking.hostName = "gateway";
        networking.useDHCP = false;
        networking.interfaces.eth1 = mkExternalInterface serverIp;
        virtualisation.interfaces.eth1 = {
          vlan = 1;
          assignIP = false;
        };

        services.pdOpenvpnServer = {
          enable = true;
          instanceName = "smoke";
          runtimeDir = "/run/openvpn-smoke";
          vpnSubnet = "10.8.0.0";
          clientToClient = true;
          pki.install = {
            sourceDir = approvedServerStageDir;
            tlsCryptSourceFile = "${testAssets}/tls-crypt.key";
          };
          clientConfigDir = "${testAssets}/ccd";
        };

        system.stateVersion = "25.11";
      };

    # Approved client with its own certificate and a fixed tunnel address.
    client1 = mkClientNode {
      hostName = "client1";
      externalIp = "192.168.1.2";
      identityDir = null;
      bundleDir = null;
      installSourceDir = "${testAssets}/staged/approved/clients/client1";
      installTlsCryptSourceFile = "${testAssets}/tls-crypt.key";
    };

    # Second approved client used to prove multiple trusted clients can connect.
    client2 = mkClientNode {
      hostName = "client2";
      externalIp = "192.168.1.3";
      identityDir = null;
      bundleDir = null;
      installSourceDir = "${testAssets}/staged/approved/clients/client2";
      installTlsCryptSourceFile = "${testAssets}/tls-crypt.key";
    };

    # Unapproved client still trusts the approved server, so any failure is about
    # client-certificate admission rather than server verification.
    rogue = mkClientNode {
      hostName = "rogue";
      externalIp = "192.168.1.4";
      identityDir = rogueIdentityDir;
      bundleDir = approvedBundleDir;
    };
  };

  testScript = ''
    start_all()

    gateway.wait_for_unit("openvpn-smoke.service")
    client1.wait_for_unit("openvpn-smoke.service")
    client2.wait_for_unit("openvpn-smoke.service")
    rogue.wait_for_unit("openvpn-smoke.service")

    gateway.succeed("test -f /run/secrets/openvpn/smoke/bundles/openvpn-ca.crt")
    gateway.succeed("test -f /run/secrets/openvpn/smoke/issued/openvpn/servers/server/server.key")
    gateway.succeed("test -f /run/secrets/openvpn/smoke/tls-crypt.key")
    client1.succeed("test -f /run/secrets/openvpn/smoke/issued/openvpn/clients/client1/client1.key")
    client1.succeed("test -f /run/secrets/openvpn/smoke/tls-crypt.key")

    gateway.wait_until_succeeds("grep -F 'CLIENT_LIST,client1,' /run/openvpn-smoke/status.log")
    gateway.wait_until_succeeds("grep -F 'CLIENT_LIST,client2,' /run/openvpn-smoke/status.log")

    client1.wait_until_succeeds("ping -c 1 10.8.0.1")
    client2.wait_until_succeeds("ping -c 1 10.8.0.1")
    gateway.wait_until_succeeds("ping -c 1 ${client1VpnIp}")
    gateway.wait_until_succeeds("ping -c 1 ${client2VpnIp}")
    client1.wait_until_succeeds("ping -c 1 ${client2VpnIp}")
    client2.wait_until_succeeds("ping -c 1 ${client1VpnIp}")

    rogue.succeed("sleep 5")
    rogue.fail("ip -o -4 addr show dev tun0 | grep -F '10.8.0.'")
    gateway.fail("grep -F 'CLIENT_LIST,rogue,' /run/openvpn-smoke/status.log")
  '';
}
