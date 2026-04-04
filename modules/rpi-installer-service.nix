{ config, disko, lib, pkgs, ... }:
let
  cfg = config.services.pdInstaller;
  keyCfg = config.services.rpiOtpLuksKey;
  privateKeyCheckExe = lib.getExe pkgs.rpi-otp-private-key;
  provisionPrivateKeyExe = lib.getExe cfg.provisionPackage;
  deriveLuksKeyExe = lib.getExe keyCfg.package;
  diskoInstallExe =
    "${disko.packages.${pkgs.stdenv.hostPlatform.system}.disko-install}/bin/disko-install";
  installCommand = pkgs.writeShellApplication {
    name = "pd-nix-install";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      if [ "$EUID" -ne 0 ]; then
        echo "This command must be run as root." >&2
        exit 1
      fi

      if [ ! -e '${cfg.disk}' ]; then
        echo "Target disk '${cfg.disk}' does not exist." >&2
        exit 1
      fi

      systemctl start --wait pd-luks-key-setup.service

      if [ ! -s '${keyCfg.keyFile}' ]; then
        echo "Expected derived LUKS key at '${keyCfg.keyFile}'." >&2
        exit 1
      fi

      exec ${diskoInstallExe} \
        --flake '${cfg.flake}#${cfg.nixosConfiguration}' \
        --mode format \
        --disk main '${cfg.disk}'
    '';
  };
in
{
  options.services.pdInstaller = {
    enable = lib.mkEnableOption "pseudo.design installer services";

    flake = lib.mkOption {
      type = lib.types.path;
      default = ../.;
      defaultText = lib.literalExpression "../.";
      description = "Flake used by the installer service.";
    };

    nixosConfiguration = lib.mkOption {
      type = lib.types.str;
      default = "ace";
      description = "NixOS configuration installed by the installer service.";
    };

    disk = lib.mkOption {
      type = lib.types.str;
      default = "/dev/nvme0n1";
      description = "Target disk passed to disko-install.";
    };

    provisionPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.rpi-otp-provision-private-key;
      defaultText = lib.literalExpression "pkgs.rpi-otp-provision-private-key";
      description = "Package used to provision the Raspberry Pi OTP private key if it is unset.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ installCommand ];

    systemd.services.pd-luks-key-setup = {
      description = "Provision the Raspberry Pi OTP private key and derive the LUKS key";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${pkgs.coreutils}/bin/install -d -m 0700 "$(${pkgs.coreutils}/bin/dirname '${keyCfg.keyFile}')"
        if ${privateKeyCheckExe} -c >/dev/null 2>&1; then
          echo "Raspberry Pi OTP private key is already provisioned."
        else
          echo "Raspberry Pi OTP private key is unset; provisioning it now."
          ${provisionPrivateKeyExe}
        fi
        ${deriveLuksKeyExe} '${keyCfg.salt}' > '${keyCfg.keyFile}'
        ${pkgs.coreutils}/bin/chmod 600 '${keyCfg.keyFile}'
      '';
    };
  };
}
