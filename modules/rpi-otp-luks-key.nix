{ pkgs, config, lib, ... }:
let
  cfg = config.services.rpiOtpLuksKey;
  writeKeyPackage = pkgs.callPackage ../packages/rpi-otp-write-derived-key.nix {
    derivePackage = cfg.package;
  };
  writeKeyExe = lib.getExe writeKeyPackage;
  writeKeyClosure = lib.filter (path: path != "") (
    lib.splitString "\n" (
      builtins.readFile "${pkgs.closureInfo { rootPaths = [ writeKeyPackage ]; }}/store-paths"
    )
  );
in
{

  options.services.rpiOtpLuksKey = {
    enable = lib.mkEnableOption "Raspberry Pi OTP LUKS Key Service";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.rpi-otp-derived-key;
      defaultText = lib.literalExpression "pkgs.rpi-otp-derived-key";
      description = "Package providing the helper that derives the key material written in initrd.";
    };
    salt = lib.mkOption {
      type = lib.types.str;
      default = "default-salt";
      description = "Salt passed to the helper. Changing this after initial install will cause disk decryption to fail.";
    };
    keyFile = lib.mkOption {
      type = lib.types.path;
      default = "/run/secrets/luks.key";
      description = "Location where the derived LUKS key is written.";
    };
  };

  config = lib.mkIf cfg.enable {
    # The service that places our key into the rootfs is needed on boot
    # necessitating the need for boot.initrd.systemd
    boot.initrd.systemd.enable = true;
    # Copy the writer package runtime closure into the initrd so arbitrary helper
    # packages can bring along their own absolute-store-path dependencies.
    boot.initrd.systemd.storePaths = writeKeyClosure;
    boot.initrd.systemd.services.rpi-otp-luks-key-initrd = {
      wantedBy = [ "initrd.target" ];
      before = [
        "cryptsetup.target"
      ];
      unitConfig.DefaultDependencies = false;
      description = "Derive the LUKS key from Raspberry Pi OTP.";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        '${writeKeyExe}' '${cfg.salt}' '${cfg.keyFile}'
      '';
    };
  };
}
