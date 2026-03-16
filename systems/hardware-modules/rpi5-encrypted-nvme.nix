{ config, pkgs, lib, ... }:
let
  cfg = config.services.rpi5EncryptedNvme;
in
{
  imports = [
    # Paths to other modules.
    # Compose this module out of smaller ones.
  ];

  options.services.rpi5EncryptedNvme = {
    enable = lib.mkEnableOption "Configure the system to create encrypted storage on the NVMe device";
    service-name = lib.mkOption {
      type = lib.types.str;
      default = "rpi-luks-key";
      description = "The name of this service, which is also the name of the user & group assigned to this service.";
      internal = true;
    };
    working-directory = lib.mkOption {
      type = lib.types.str;
      default = "/run/rpi-luks-key";
      description = "The working directory of this service.  Ideally, it should not persist through a reboot.";
      internal = true;
    };
    key-file-name = lib.mkOption {
      type = lib.types.str;
      default = "rpi-private-key.sha256";
      description = "Name of the luks key file.";
      internal = true;
    };
  };

  config = lib.mkIf cfg.enable {
    # The LUKS key is a sha256sum of this device's OTP private key.
    systemd.services."$(cfg.service-name)" = {
      unitConfig = {
        RequiresMountsFor = cfg.working-directory;
      };
      serviceConfig = {
        Type = "oneshot";
        User = cfg.service-name;
        Group = cfg.service-name;
        WorkingDirectory = cfg.working-directory;
        RemainAfterExit = true;
        ExecStartPre = ''
          # This command will fail if the OTP private key hasn't been set (e.g. is all 0s)
          /bin/sh -c "${pkgs.raspberrypi-eeprom}/bin/rpi-otp-private-key -c > /dev/null"
        '';
        ExecStart = ''
          # Generate our LUKS key file without exposing our device unique private key by generating a sha256sum of the private key.
          /bin/sh -c "${pkgs.raspberrypi-eeprom}/bin/rpi-otp-private-key | sha256sum | tr -d ' -' > '${cfg.key-file-name}' && chmod 600 '${cfg.key-file-name}'"
        '';
      };
    };
  };
}
