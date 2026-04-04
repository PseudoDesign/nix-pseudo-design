{ lib, testers, pkgs }:
let
  mockLuksGetKeyBin = pkgs.writeShellScriptBin "mock-rpi-otp-luks-key" ''
    echo "12345"
  '';
in
testers.runNixOSTest {
  name = "rpi-otp-luks-key service writes output of luksGetKeyBin to luksKeyFile";
  nodes.rpi =
    { ... }:
    {
      imports = [ ../modules/rpi-otp-luks-key ];
      services.rpiOtpLuksKey.enable = true;
      services.rpiOtpLuksKey.luksKeyGetBin = "${mockLuksGetKeyBin}/bin/mock-rpi-otp-luks-key";
      services.rpiOtpLuksKey.luksKeyFile = "/run/mock/secrets/luks.key";
    };

  testScript = ''
    start_all()
    rpi.wait_for_unit("default.target")
    rpi.succeed('[ -f "/run/mock/secrets/luks.key" ]')
    rpi.succeed('[ "$(tr -d "\\n" < /run/mock/secrets/luks.key)" = "12345" ]')
  '';
}
