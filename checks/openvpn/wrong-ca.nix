{ testers, pkgs, ... }:
let
  mkOpenvpnTestAssets = pkgs.callPackage ./lib/test-assets.nix { };
  testAssets = mkOpenvpnTestAssets {
    name = "openvpn-wrong-ca";
    approvedRootCommonName = "OpenVPN Wrong-CA Approved Root CA";
    approvedIntermediateCommonName = "OpenVPN Wrong-CA Approved Intermediate CA";
    rogueRootCommonName = "OpenVPN Wrong-CA Rogue Root CA";
    rogueIntermediateCommonName = "OpenVPN Wrong-CA Rogue Intermediate CA";
    serverCommonName = "openvpn-wrong-ca-server";
    approvedClients = [ "approved" ];
    rogueClients = [ "rogue" ];
    ccdAssignments = {
      approved = "10.9.0.10";
    };
  };

  serverIp = "192.168.2.1";
  instanceName = "wrong-ca";
  vpnSubnet = "10.9.0.0";
  approvedVpnIp = "10.9.0.10";
  statusFile = "/run/openvpn-wrong-ca/status.log";
  approvedWorkspace = "${testAssets}/approved";
  rogueWorkspace = "${testAssets}/rogue";
  approvedCaBundleFile = "${approvedWorkspace}/bundles/openvpn-ca.crt";
  approvedCrlFile = "${approvedWorkspace}/bundles/openvpn-ca.crl.pem";
  serverCertDir = "${approvedWorkspace}/issued/openvpn/servers/server";

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
      caCertFile,
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
        inherit caCertFile;
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
          runtimeDir = "/run/openvpn-wrong-ca";
          inherit vpnSubnet;
          caCertFile = approvedCaBundleFile;
          crlFile = approvedCrlFile;
          serverCertFile = "${serverCertDir}/server.crt";
          serverKeyFile = "${serverCertDir}/server.key";
          tlsCryptKeyFile = "${testAssets}/tls-crypt.key";
          clientConfigDir = "${testAssets}/ccd";
        };

        system.stateVersion = "25.11";
      };

    # Approved client proves the server is working while the rogue client is denied.
    approved = mkClientNode {
      hostName = "approved";
      externalIp = "192.168.2.2";
      certDir = "${approvedWorkspace}/issued/openvpn/clients/approved";
      caCertFile = approvedCaBundleFile;
      certName = "approved";
    };

    # Rogue client still trusts the approved server, so rejection isolates the
    # server-side client-CA policy rather than the server certificate chain.
    rogue = mkClientNode {
      hostName = "rogue";
      externalIp = "192.168.2.3";
      certDir = "${rogueWorkspace}/issued/openvpn/clients/rogue";
      caCertFile = approvedCaBundleFile;
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
