{ pkgs, config, lib,  ... }: 
let
  cfg = config.services.rpiOtpLuksKey;
in
{

  options.services.rpiOtpLuksKey = {
    enable = lib.mkEnableOption "Raspberry Pi OTP LUKS Key Service";
    luksKeyGetBin = lib.mkOption {
      type = lib.types.path;
      default = "${pkgs.rpi-otp-private-key}/bin/rpi-otp-private-key";
      description = "Path to the binary used to populate the LUKS key from device-unique storage";
    };
    luksKeySalt = lib.mkOption {
      type = lib.types.str;
      default = "default-salt";
      description = "The salt value passed to luksKeyGetBin. Changing this after initial install will cause the disk decryption to fail.";
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
    boot.initrd.systemd.services.rpi-otp-luks-key-initrd = {
      wantedBy = [ "initrd.target" ];
      before = [
        "cryptsetup.target"
      ];
      unitConfig.DefaultDependencies = false;
          description = "Get the luks key from Raspberry Pi OTP.";
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        install -d -m 0700 "$(${pkgs.coreutils}/bin/dirname '${cfg.luksKeyFile}')"
        '${cfg.luksKeyGetBin}' '${cfg.luksKeySalt}' > '${cfg.luksKeyFile}'
        chmod 600 '${cfg.luksKeyFile}'
      '';
    };
  };
}