{ lib, testers, pkgs }:
let
  mockLuksKeyPackage = pkgs.writeShellScriptBin "rpi-otp-luks-key" ''
    echo "12345"
  '';
in
testers.runNixOSTest {
  name = "rpi-otp-luks-key service writes output of configured helper to luksKeyFile";
  nodes.rpi =
    { ... }:
    {
      imports = [ ../modules/rpi-otp-luks-key ];
      services.rpiOtpLuksKey.enable = true;
      services.rpiOtpLuksKey.package = mockLuksKeyPackage;
      services.rpiOtpLuksKey.luksKeyFile = "/run/mock/package/luks.key";
    };

  testScript = ''
    start_all()
    rpi.wait_for_unit("default.target")
    rpi.succeed('[ -f "/run/mock/package/luks.key" ]')
    rpi.succeed('[ "$(tr -d "\\n" < /run/mock/package/luks.key)" = "12345" ]')
  '';
}
