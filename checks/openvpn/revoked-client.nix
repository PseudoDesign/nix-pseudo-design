{ testers, pkgs, ... }:
let
  mkOpenvpnTestAssets = pkgs.callPackage ./lib/test-assets.nix { };
  testAssets = mkOpenvpnTestAssets {
    name = "openvpn-revoked-client";
    approvedRootCommonName = "OpenVPN Revoked Approved Root CA";
    approvedIntermediateCommonName = "OpenVPN Revoked Approved Intermediate CA";
    rogueRootCommonName = "OpenVPN Revoked Rogue Root CA";
    rogueIntermediateCommonName = "OpenVPN Revoked Rogue Intermediate CA";
    serverCommonName = "openvpn-revoked-server";
    approvedClients = [
      "active"
      "revoked"
    ];
    revokedApprovedClients = [ "revoked" ];
    ccdAssignments = {
      active = "10.10.0.10";
      revoked = "10.10.0.11";
    };
  };

  serverIp = "192.168.3.1";
  instanceName = "revoked-client";
  vpnSubnet = "10.10.0.0";
  activeVpnIp = "10.10.0.10";
  statusFile = "/run/openvpn-revoked/status.log";
  approvedServerStageDir = "${testAssets}/staged/approved/server";
  approvedServerIdentityKeySourceFile = "${testAssets}/endpoints/approved/servers/server/active/server.key";

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
      certName,
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
        inherit instanceName;
        remoteHost = serverIp;
        pki.install = {
          sourceDir = "${testAssets}/staged/approved/clients/${certName}";
          identityKeySourceFile = "${testAssets}/endpoints/approved/clients/${certName}/active/${certName}.key";
          tlsCryptSourceFile = "${testAssets}/tls-crypt.key";
        };
        verifyX509Name = "openvpn-revoked-server";
      };

      system.stateVersion = "25.11";
    };
in
testers.runNixOSTest {
  name = "openvpn-revoked-client";

  nodes = {
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
          inherit instanceName;
          runtimeDir = "/run/openvpn-revoked";
          inherit vpnSubnet;
          pki.install = {
            sourceDir = approvedServerStageDir;
            identityKeySourceFile = approvedServerIdentityKeySourceFile;
            tlsCryptSourceFile = "${testAssets}/tls-crypt.key";
          };
          clientConfigDir = "${testAssets}/ccd";
        };

        system.stateVersion = "25.11";
      };

    active = mkClientNode {
      hostName = "active";
      externalIp = "192.168.3.2";
      certName = "active";
    };

    revoked = mkClientNode {
      hostName = "revoked";
      externalIp = "192.168.3.3";
      certName = "revoked";
    };
  };

  testScript = ''
    start_all()

    gateway.wait_for_unit("openvpn-revoked-client.service")
    active.wait_for_unit("openvpn-revoked-client.service")
    revoked.wait_for_unit("openvpn-revoked-client.service")

    gateway.wait_until_succeeds("grep -F 'CLIENT_LIST,active,' ${statusFile}")
    active.wait_until_succeeds("ping -c 1 10.10.0.1")
    gateway.wait_until_succeeds("ping -c 1 ${activeVpnIp}")

    revoked.succeed("sleep 5")
    revoked.fail("ip -o -4 addr show dev tun | grep -F '10.10.0.'")
    gateway.fail("grep -F 'CLIENT_LIST,revoked,' ${statusFile}")
  '';
}
