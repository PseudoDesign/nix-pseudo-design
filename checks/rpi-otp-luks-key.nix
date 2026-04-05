{ lib, testers, pkgs }:
let
  mockDerivedKeyPackage = pkgs.writeShellScriptBin "rpi-otp-derived-key" ''
    echo "12345"
  '';
in
testers.runNixOSTest {
  name = "rpi-otp-luks-key service writes output of configured helper to keyFile";
  nodes.rpi =
    { ... }:
    {
      imports = [ ../modules/rpi-otp-luks-key ];
      services.rpiOtpLuksKey.enable = true;
      services.rpiOtpLuksKey.package = mockDerivedKeyPackage;
      services.rpiOtpLuksKey.keyFile = "/run/mock/package/luks.key";
    };

  testScript = ''
    start_all()
    rpi.wait_for_unit("default.target")
    rpi.succeed('[ -f "/run/mock/package/luks.key" ]')
    rpi.succeed('[ "$(tr -d "\\n" < /run/mock/package/luks.key)" = "12345" ]')
  '';
}
