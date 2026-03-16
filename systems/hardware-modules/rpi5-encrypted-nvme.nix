{ config, pkgs, ... }:
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
      description = "The name of the user & group used by this module";
      internal = true;
    };
  };

  config = lib.mkIf cfg.enable {
    # The LUKS key is a sha256sum of this device's OTP private key.
    systemd.services."$(cfg.service-name)" = {
      unitConfig = {
        RequiresMountsFor = "/run/rpi-luks-key";
      };
      serviceConfig = {
        Type = "oneshot";
        User = "rpi-luks-key";
        Group = "rpi-luks-key";
        WorkingDirectory = "/run/rpi-luks-key";
        RemainAfterExit = true;
        ExecStart = ''
          # 
          '';
      };
    }
  };
}
