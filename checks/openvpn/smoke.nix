{ testers, pkgs, ... }:
let
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
  serverCertDir = "${approvedServerStageDir}/issued/openvpn/servers/server";

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

      services.pdOpenvpnClient = {
        enable = true;
        instanceName = "smoke";
        remoteHost = serverIp;
        pki.bundleDir = bundleDir;
        pki.identityDir = identityDir;
        tlsCryptKeyFile = "${testAssets}/tls-crypt.key";
        verifyX509Name = "openvpn-smoke-server";
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
          pki.bundleDir = approvedBundleDir;
          pki.identityDir = serverCertDir;
          tlsCryptKeyFile = "${testAssets}/tls-crypt.key";
          clientConfigDir = "${testAssets}/ccd";
        };

        system.stateVersion = "25.11";
      };

    # Approved client with its own certificate and a fixed tunnel address.
    client1 = mkClientNode {
      hostName = "client1";
      externalIp = "192.168.1.2";
      identityDir = "${testAssets}/staged/approved/clients/client1/issued/openvpn/clients/client1";
      bundleDir = "${testAssets}/staged/approved/clients/client1/bundles";
    };

    # Second approved client used to prove multiple trusted clients can connect.
    client2 = mkClientNode {
      hostName = "client2";
      externalIp = "192.168.1.3";
      identityDir = "${testAssets}/staged/approved/clients/client2/issued/openvpn/clients/client2";
      bundleDir = "${testAssets}/staged/approved/clients/client2/bundles";
    };

    # Unapproved client still trusts the approved server, so any failure is about
    # client-certificate admission rather than server verification.
    rogue = mkClientNode {
      hostName = "rogue";
      externalIp = "192.168.1.4";
      identityDir = "${testAssets}/staged/rogue/clients/rogue/issued/openvpn/clients/rogue";
      bundleDir = approvedBundleDir;
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
