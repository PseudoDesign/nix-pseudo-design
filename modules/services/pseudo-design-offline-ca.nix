{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.pseudoDesign.offlineCa;
  inherit (lib)
    escapeShellArg
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  caTools = pkgs.callPackage ../../packages/pseudo-design-ca-tools { };
  stateDirArg = escapeShellArg cfg.stateDir;
  exportDirArg = escapeShellArg cfg.exportDir;

  requireRoot = ''
    if [ "$(${pkgs.coreutils}/bin/id -u)" -ne 0 ]; then
      printf 'error: run this command with sudo\n' >&2
      exit 1
    fi
  '';

  caBootstrap = pkgs.writeShellApplication {
    name = "pseudo-design-ca-bootstrap";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.openssl
      pkgs.step-cli
      pkgs.step-kms-plugin
    ];
    text = ''
      if [ "''${1:-}" = "-h" ] || [ "''${1:-}" = "--help" ]; then
        printf 'Usage: sudo pseudo-design-ca-bootstrap\n'
        exit 0
      fi

      if [ "$#" -ne 0 ]; then
        printf 'Usage: sudo pseudo-design-ca-bootstrap\n' >&2
        exit 2
      fi

      ${requireRoot}

      export PSEUDO_DESIGN_CA_BOOTSTRAP_NEXT="sudo pseudo-design-ca-export"
      exec ${caTools}/libexec/pseudo-design-ca/bootstrap-offline-ca.sh ${stateDirArg}
    '';
  };

  caExport = pkgs.writeShellApplication {
    name = "pseudo-design-ca-export";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      if [ "''${1:-}" = "-h" ] || [ "''${1:-}" = "--help" ]; then
        printf 'Usage: sudo pseudo-design-ca-export\n'
        exit 0
      fi

      if [ "$#" -ne 0 ]; then
        printf 'Usage: sudo pseudo-design-ca-export\n' >&2
        exit 2
      fi

      ${requireRoot}

      exec ${caTools}/libexec/pseudo-design-ca/export-artifacts.sh ${stateDirArg} ${exportDirArg}
    '';
  };

  caSignIntermediate = pkgs.writeShellApplication {
    name = "pseudo-design-ca-sign-intermediate";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.openssl
      pkgs.step-cli
      pkgs.step-kms-plugin
    ];
    text = ''
      if [ "''${1:-}" = "-h" ] || [ "''${1:-}" = "--help" ]; then
        printf 'Usage: sudo pseudo-design-ca-sign-intermediate CSR OUT_CERT\n'
        exit 0
      fi

      if [ "$#" -ne 2 ]; then
        printf 'Usage: sudo pseudo-design-ca-sign-intermediate CSR OUT_CERT\n' >&2
        exit 2
      fi

      ${requireRoot}

      exec ${caTools}/libexec/pseudo-design-ca/sign-intermediate.sh "$1" "$2" ${stateDirArg}
    '';
  };

  caMintToken = pkgs.writeShellApplication {
    name = "pseudo-design-ca-mint-token";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.step-cli
    ];
    text = ''
      if [ "''${1:-}" = "-h" ] || [ "''${1:-}" = "--help" ]; then
        printf 'Usage: sudo pseudo-design-ca-mint-token HOST\n'
        exit 0
      fi

      if [ "$#" -ne 1 ]; then
        printf 'Usage: sudo pseudo-design-ca-mint-token HOST\n' >&2
        exit 2
      fi

      ${requireRoot}

      exec ${caTools}/libexec/pseudo-design-ca/mint-device-token.sh "$1" ${stateDirArg}
    '';
  };
in
{
  options.services.pseudoDesign.offlineCa = {
    enable = mkEnableOption "pseudo.design offline root CA operations";

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/pseudo-design/offline-ca";
      description = "Root-only directory containing offline CA private state.";
    };

    exportDir = mkOption {
      type = types.str;
      default = "${cfg.stateDir}/export";
      description = "Directory where export bundles for removable-media transfer are written.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.openssl
      pkgs.step-cli
      pkgs.step-kms-plugin
      caBootstrap
      caExport
      caSignIntermediate
      caMintToken
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0700 root root -"
      "d ${cfg.exportDir} 0700 root root -"
    ];
  };
}
