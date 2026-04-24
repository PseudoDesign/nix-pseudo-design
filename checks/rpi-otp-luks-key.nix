{ lib, nixos-raspberrypi, testers, pkgs }:
let
  testSaltFile = pkgs.writeText "rpi-otp-derived-key-test-salt" "test-salt";
  mockDerivedKeyPackage = pkgs.writeShellApplication {
    name = "rpi-otp-derived-key";
    text = ''
      case "$1" in
        --format)
          [ "$2" = "hex" ] || exit 64
          shift 2
          ;;
        *)
          exit 64
          ;;
      esac

      case "$1" in
        --salt-file)
          [ -r "$2" ] || exit 1
          shift 2
          ;;
        *)
          exit 64
          ;;
      esac

      [ "$#" -eq 0 ] || exit 64
      echo "12345"
    '';
  };
in
testers.runNixOSTest {
  name = "rpi-otp-derived-key luks secret writes output of configured helper to keyFile";
  nodes.rpi =
    { ... }:
    {
      imports = [ nixos-raspberrypi.nixosModules.rpi-otp-derived-key ];
      services.rpiOtpDerivedKey = {
        enable = true;
        package = mockDerivedKeyPackage;
        generateSalt = false;
        saltFile = "${testSaltFile}";
        secrets.luks = {
          format = "hex";
          path = "/run/mock/package/luks.key";
        };
      };
    };

  testScript = ''
    start_all()
    rpi.wait_for_unit("default.target")
    rpi.succeed('[ -f "/run/mock/package/luks.key" ]')
    rpi.succeed('[ "$(tr -d "\\n" < /run/mock/package/luks.key)" = "12345" ]')
  '';
}
