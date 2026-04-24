{ config, disko, lib, pkgs, ... }:
let
  cfg = config.services.pdInstaller;
  keyCfg = config.services.rpiOtpDerivedKey;
  luksSecret = keyCfg.secrets.luks or null;
  luksKeyFile = if luksSecret != null then luksSecret.path else "/run/secrets/luks.key";
  saltSource = if keyCfg.initrdSaltSource != null then keyCfg.initrdSaltSource else keyCfg.saltFile;
  defaultProvisionPackage = pkgs.writeShellApplication {
    name = "pd-rpi-otp-provision-private-key";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.openssl
      pkgs.rpi-otp-private-key
    ];
    text = ''
      tmpKey="$(${pkgs.coreutils}/bin/mktemp)"
      cleanup() {
        ${pkgs.coreutils}/bin/rm -f "$tmpKey"
      }
      trap cleanup EXIT

      ${pkgs.openssl}/bin/openssl ecparam \
        -name prime256v1 \
        -genkey \
        -noout \
        -out "$tmpKey"

      privateKeyHex="$(
        ${pkgs.openssl}/bin/openssl ec -in "$tmpKey" -text -noout \
          | ${pkgs.gawk}/bin/awk '/priv:/{flag=1; next} /pub:/{flag=0} flag' \
          | ${pkgs.coreutils}/bin/tr -d ' \n:' \
          | ${pkgs.coreutils}/bin/head -n1
      )"

      if [ "''${#privateKeyHex}" -ne 64 ]; then
        echo "Failed to generate a valid P-256 OTP private key." >&2
        exit 2
      fi

      exec ${lib.getExe pkgs.rpi-otp-private-key} -w "$privateKeyHex"
    '';
  };
  # Expose manual key setup as a standalone command for debugging/recovery.
  setupCommand = pkgs.callPackage ../packages/pd-luks-key-setup.nix {
    derivePackage = keyCfg.package;
    inherit saltSource;
    keyFile = luksKeyFile;
  };
  # Keep the interactive installer command in a package; this module just injects
  # the host-specific configuration values it should operate with.
  installCommand = pkgs.callPackage ../packages/pd-nix-install.nix {
    provisionPackage = cfg.provisionPackage;
    setupPackage = setupCommand;
    diskoInstallPackage = disko.packages.${pkgs.stdenv.hostPlatform.system}.disko-install;
    flakePath = cfg.flake;
    nixosConfiguration = cfg.nixosConfiguration;
    disk = cfg.disk;
    keyFile = luksKeyFile;
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
      default = defaultProvisionPackage;
      description = "Package used to provision the Raspberry Pi OTP private key if it is unset.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = luksSecret != null;
        message = "services.pdInstaller.enable requires services.rpiOtpDerivedKey.secrets.luks to be configured.";
      }
      {
        assertion = luksSecret == null || luksSecret.format == "hex";
        message = "services.pdInstaller.enable requires services.rpiOtpDerivedKey.secrets.luks.format = \"hex\".";
      }
    ];

    # Installing the commands into PATH is the whole point of this module now.
    environment.systemPackages = [
      installCommand
      setupCommand
    ];
  };
}
