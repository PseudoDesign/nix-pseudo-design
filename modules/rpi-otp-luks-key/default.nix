{ pkgs, config, lib, ... }:
let
  cfg = config.services.rpiOtpLuksKey;
  luksKeyGetExe = lib.getExe cfg.package;
in
{

  options.services.rpiOtpLuksKey = {
    enable = lib.mkEnableOption "Raspberry Pi OTP LUKS Key Service";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.rpi-otp-luks-key;
      defaultText = lib.literalExpression "pkgs.rpi-otp-luks-key";
      description = "Package providing the helper that derives the LUKS key in initrd.";
    };
    luksKeySalt = lib.mkOption {
      type = lib.types.str;
      default = "default-salt";
      description = "The salt value passed to the helper. Changing this after initial install will cause the disk decryption to fail.";
    };
    luksKeyFile = lib.mkOption {
      type = lib.types.path;
      default = "/run/secrets/luks.key";
      description = "The location to save the LUKS key";
    };
  };

  config = lib.mkIf cfg.enable {
    # The service that places our key into the rootfs is needed on boot
    # necessitating the need for boot.initrd.systemd
    boot.initrd.systemd.enable = true;
    # Explicitly copy the helper into the initrd so the stage-1 service can execute it.
    boot.initrd.systemd.storePaths = [ luksKeyGetExe ];
    boot.initrd.systemd.services.rpi-otp-luks-key-initrd = {
      wantedBy = [ "initrd.target" ];
      before = [
        "cryptsetup.target"
      ];
      unitConfig.DefaultDependencies = false;
      description = "Get the luks key from Raspberry Pi OTP.";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        install -d -m 0700 "$(${pkgs.coreutils}/bin/dirname '${cfg.luksKeyFile}')"
        '${luksKeyGetExe}' '${cfg.luksKeySalt}' > '${cfg.luksKeyFile}'
        chmod 600 '${cfg.luksKeyFile}'
      '';
    };
  };
}
