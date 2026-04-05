{ config, disko, lib, pkgs, ... }:
let
  cfg = config.services.pdInstaller;
  keyCfg = config.services.rpiOtpLuksKey;
  # Build the shared key-writer around the currently configured derivation helper.
  writeKeyPackage = pkgs.callPackage ../packages/rpi-otp-write-derived-key.nix {
    derivePackage = keyCfg.package;
  };
  # Expose manual key setup as a standalone command for debugging/recovery.
  setupCommand = pkgs.callPackage ../packages/pd-luks-key-setup.nix {
    inherit writeKeyPackage;
    salt = keyCfg.salt;
    keyFile = keyCfg.keyFile;
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
    keyFile = keyCfg.keyFile;
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
    # Installing the commands into PATH is the whole point of this module now.
    environment.systemPackages = [
      installCommand
      setupCommand
    ];
  };
}
