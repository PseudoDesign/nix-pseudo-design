{ pkgs, ... }:
pkgs.testers.runNixOSTest {
    # `testScript` is a Python script using unittest-like statements.
    # See the docs here: https://nixos.org/manual/nixos/stable/index.html#sec-nixos-tests is close
    inherit testScript;
    name = "OpenVPN Configuration Tests";
    # `nodes` define the VMs we spin up as part of this test.
    nodes = {
      # OpenVPN server
      server = 
        { pkgs, ... }:
        {
          imports = [
            ../configurations/openvpn/server.nix
          ];
          environment.systemPackages = [ pkgs.openssl pkgs.coreutils ];
        };
      # OpenVPN client running a webserver
      client_webserver = 
        { pkgs, ... }:
        {
          imports = [
            ../configurations/openvpn/client.nix
          ];
        };
      # OpenVPN client downloading from the webserver
      client = 
        { pkgs, ... }:
        {
          imports = [
            ../configurations/openvpn/client.nix
          ];
        };
    };
  }