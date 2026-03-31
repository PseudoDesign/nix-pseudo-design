{ lib, testers }:
let
  overlayMocks = (

  );
in
{
  service = testers.runNixOSTest {
    name = "Test for rpi-otp-luks-key initrd service";
    nodes.rpi =
      { ... }:
      {
        imports = [ ../modules/rpi-otp-luks-key ];
        services.openssh.enable = true;
        services.openssh.hostKeys = [
          {
            type = "rsa";
            bits = 4096;
            path = testAssets + "/ssh-key";
          }
        ];
        sops.defaultSopsFile = testAssets + "/secrets.yaml";
        sops.secrets.test_key = { };
      };

    testScript = ''
      start_all()
      server.succeed("cat /run/secrets/test_key | grep -q test_value")
    '';
  };
}