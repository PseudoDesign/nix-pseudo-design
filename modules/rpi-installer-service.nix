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
      readonly EX_USAGE=64
      readonly EX_NOINPUT=66
      readonly EX_SOFTWARE=70
      readonly EX_NOPERM=77
      readonly DEFAULT_FLAKE='${cfg.flake}#${cfg.nixosConfiguration}'
      readonly REMOTE_FLAKE='github:pseudodesign/nix-pseudo-design'

      flakeRef="$DEFAULT_FLAKE"

      if [ "$#" -gt 1 ]; then
        echo "Usage: pd-nix-install [branch]" >&2
        exit "$EX_USAGE"
      fi

      if [ "$#" -eq 1 ]; then
        flakeRef="$REMOTE_FLAKE?ref=$1#${cfg.nixosConfiguration}"
      fi

      if [ "$EUID" -ne 0 ]; then
        echo "This command must be run as root." >&2
        exit "$EX_NOPERM"
      fi

      if [ ! -e '${cfg.disk}' ]; then
        echo "Target disk '${cfg.disk}' does not exist." >&2
        exit "$EX_NOINPUT"
      fi

      if [ ! -t 0 ]; then
        echo "This command requires an interactive terminal for confirmation." >&2
        exit "$EX_NOINPUT"
      fi

      echo "About to install NixOS with the following settings:"
      echo "  source flake: $flakeRef"
      echo "  configuration: ${cfg.nixosConfiguration}"
      echo "  target disk: ${cfg.disk}"
      echo "  derived key file: ${keyCfg.keyFile}"
      echo
      echo "This will:"
      echo "  1. Ensure the Raspberry Pi OTP private key is provisioned if it is unset."
      echo "  2. Derive the LUKS key into ${keyCfg.keyFile}."
      echo "  3. Run disko-install in format mode against ${cfg.disk}."
      echo
      echo "WARNING: This may permanently program OTP and will continue into disk formatting."
      echo "Type YES to continue or anything else to cancel."
      read -r confirmation
      if [ "$confirmation" != "YES" ]; then
        echo "Cancelled."
        exit 1
      fi

      systemctl start pd-luks-key-setup.service

      if [ ! -s '${keyCfg.keyFile}' ]; then
        echo "Expected derived LUKS key at '${keyCfg.keyFile}'." >&2
        exit "$EX_SOFTWARE"
      fi

      exec ${diskoInstallExe} \
        --flake "$flakeRef" \
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
