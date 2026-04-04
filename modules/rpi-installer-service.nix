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
      readonly FLAKE_PATH='${cfg.flake}'
      readonly DEFAULT_CONFIGURATION='${cfg.nixosConfiguration}'

      configurationName="$DEFAULT_CONFIGURATION"

      if [ "$#" -gt 1 ]; then
        echo "Usage: pd-nix-install [configuration]" >&2
        exit "$EX_USAGE"
      fi

      if [ "$#" -eq 1 ]; then
        configurationName="$1"
      fi

      flakeRef="$FLAKE_PATH#$configurationName"

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
      echo "  configuration: $configurationName"
      echo "  target disk: ${cfg.disk}"
      echo "  derived key file: ${keyCfg.keyFile}"
      echo
      echo "This will:"
      echo "  1. Provision the Raspberry Pi OTP private key if it is unset."
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

      if ! ${privateKeyCheckExe} -c >/dev/null 2>&1; then
        echo "Raspberry Pi OTP private key is unset; provisioning it now."
        ${provisionPrivateKeyExe}
      fi

      echo "Deriving the LUKS key into ${keyCfg.keyFile}."
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
      description = "Local flake used by the installer command by default.";
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
      description = "Derive the LUKS key from the Raspberry Pi OTP private key";
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        keyDir="$(${pkgs.coreutils}/bin/dirname '${keyCfg.keyFile}')"
        ${pkgs.coreutils}/bin/install -d -m 0700 "$keyDir"
        if ! ${privateKeyCheckExe} -c >/dev/null 2>&1; then
          echo "Raspberry Pi OTP private key is not provisioned. Run pd-nix-install to provision it first." >&2
          exit 1
        fi
        tmpKeyFile="$(${pkgs.coreutils}/bin/mktemp "$keyDir/.luks.key.XXXXXX")"
        cleanup() {
          ${pkgs.coreutils}/bin/rm -f "$tmpKeyFile"
        }
        trap cleanup EXIT
        ${deriveLuksKeyExe} '${keyCfg.salt}' > "$tmpKeyFile"
        ${pkgs.coreutils}/bin/chmod 600 "$tmpKeyFile"
        ${pkgs.coreutils}/bin/mv -f "$tmpKeyFile" '${keyCfg.keyFile}'
        trap - EXIT
      '';
    };
  };
}
