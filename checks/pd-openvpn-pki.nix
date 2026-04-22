{ pkgs, testers }:
testers.runNixOSTest {
  name = "pd-openvpn-pki offline root intermediate and leaf workflow";

  nodes = {
    root =
      { ... }:
      {
        imports = [ ../modules/pd-openvpn-root-ca.nix ];
        services.pdOpenvpnRootCA.enable = true;
        system.stateVersion = "25.11";
      };

    intermediate =
      { ... }:
      {
        imports = [ ../modules/pd-openvpn-intermediate-ca.nix ];
        services.pdOpenvpnIntermediateCA.enable = true;
        system.stateVersion = "25.11";
      };

    server =
      { ... }:
      {
        imports = [ ../modules/pd-openvpn-leaf.nix ];
        networking.hostName = "openvpn-server";
        services.pdOpenvpnLeaf = {
          enable = true;
          subject = "/CN=openvpn-server";
          subjectAltNames = [ "DNS:openvpn-server.internal" ];
        };
        system.stateVersion = "25.11";
      };

    client =
      { ... }:
      {
        imports = [ ../modules/pd-openvpn-leaf.nix ];
        networking.hostName = "openvpn-client";
        services.pdOpenvpnLeaf = {
          enable = true;
          subject = "/CN=openvpn-client";
          autoGenerate = false;
        };
        system.stateVersion = "25.11";
      };
  };

  testScript = ''
    import shlex

    def copy_between(source_machine, source_path, target_machine, target_path):
        payload = source_machine.succeed(f"base64 -w0 {shlex.quote(source_path)}").strip()
        target_machine.succeed(
            f"printf '%s' '{payload}' | base64 -d > {shlex.quote(target_path)}"
        )

    start_all()

    root = machines["root"]
    intermediate = machines["intermediate"]
    server = machines["server"]
    client = machines["client"]

    for machine_name in ("root", "intermediate", "server", "client"):
        machine = machines[machine_name]
        machine.wait_for_unit("multi-user.target")

    root.succeed("pd-openvpn-root-ca-init")
    intermediate.succeed("pd-openvpn-intermediate-ca-init")
    server.wait_for_unit("pd-openvpn-leaf-init.service")
    client.succeed("pd-openvpn-leaf-init")

    copy_between(
        intermediate,
        "/var/lib/pd-openvpn/intermediate-ca/csr/intermediate-ca.csr",
        root,
        "/tmp/intermediate-ca.csr",
    )
    root.succeed(
        "pd-openvpn-root-ca-sign-intermediate /tmp/intermediate-ca.csr /tmp/intermediate-ca.crt"
    )

    copy_between(root, "/tmp/intermediate-ca.crt", intermediate, "/tmp/intermediate-ca.crt")
    copy_between(root, "/var/lib/pd-openvpn/root-ca/certs/root-ca.crt", intermediate, "/tmp/root-ca.crt")
    intermediate.succeed(
        "pd-openvpn-intermediate-ca-import-chain /tmp/root-ca.crt /tmp/intermediate-ca.crt"
    )

    copy_between(
        server,
        "/var/lib/pd-openvpn/leaf/csr/openvpn-server.csr",
        intermediate,
        "/tmp/openvpn-server.csr",
    )
    intermediate.succeed(
        "pd-openvpn-intermediate-ca-sign-server /tmp/openvpn-server.csr /tmp/openvpn-server.crt"
    )
    copy_between(intermediate, "/tmp/openvpn-server.crt", server, "/tmp/openvpn-server.crt")
    copy_between(
        intermediate,
        "/var/lib/pd-openvpn/intermediate-ca/certs/ca-chain.crt",
        server,
        "/tmp/ca-chain.crt",
    )
    server.succeed(
        "pd-openvpn-leaf-import-certificate /tmp/openvpn-server.crt /tmp/ca-chain.crt"
    )
    server.succeed("pd-openvpn-leaf-verify server")
    server.succeed(
        "openssl x509 -in /var/lib/pd-openvpn/leaf/certs/openvpn-server.crt -noout -text | grep -F 'TLS Web Server Authentication'"
    )
    server.succeed(
        "openssl x509 -in /var/lib/pd-openvpn/leaf/certs/openvpn-server.crt -noout -text | grep -F 'DNS:openvpn-server.internal'"
    )

    copy_between(
        client,
        "/var/lib/pd-openvpn/leaf/csr/openvpn-client.csr",
        intermediate,
        "/tmp/openvpn-client.csr",
    )
    intermediate.succeed(
        "pd-openvpn-intermediate-ca-sign-client /tmp/openvpn-client.csr /tmp/openvpn-client.crt"
    )
    copy_between(intermediate, "/tmp/openvpn-client.crt", client, "/tmp/openvpn-client.crt")
    copy_between(
        intermediate,
        "/var/lib/pd-openvpn/intermediate-ca/certs/ca-chain.crt",
        client,
        "/tmp/ca-chain.crt",
    )
    client.succeed(
        "pd-openvpn-leaf-import-certificate /tmp/openvpn-client.crt /tmp/ca-chain.crt"
    )
    client.succeed("pd-openvpn-leaf-verify client")
    client.succeed(
        "openssl x509 -in /var/lib/pd-openvpn/leaf/certs/openvpn-client.crt -noout -text | grep -F 'TLS Web Client Authentication'"
    )
  '';
}
