{ config, lib, pkgs, ... }:
let
  cfg = config.services.pdOpenvpnLeaf;
  tools = pkgs.callPackage ../packages/pd-openvpn-leaf.nix {
    inherit
      (cfg)
      identityName
      keyBits
      passphraseFile
      stateDir
      subject
      subjectAltNames
      ;
  };
in
{
  options.services.pdOpenvpnLeaf = {
    enable = lib.mkEnableOption "OpenVPN leaf certificate tooling for generating a local keypair and CSR";

    autoGenerate = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Generate the local private key and CSR during boot if they are missing.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/pd-openvpn/leaf";
      description = "Runtime state directory used for the endpoint key, CSR, certificate, and imported chain.";
    };

    identityName = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "Filename stem used for the generated key, CSR, and certificate.";
    };

    subject = lib.mkOption {
      type = lib.types.str;
      default = "/CN=${config.networking.hostName}";
      description = "OpenSSL subject used when generating the endpoint CSR.";
    };

    subjectAltNames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "DNS:vpn.example.internal"
        "IP:10.0.0.1"
      ];
      description = "Optional subjectAltName entries embedded in the CSR and copied into the signed certificate.";
    };

    passphraseFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional runtime path to a file containing the leaf private key passphrase.";
    };

    keyBits = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4096;
      description = "RSA key size used when generating the leaf private key.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0700 root root -"
      "d ${cfg.stateDir}/private 0700 root root -"
      "d ${cfg.stateDir}/csr 0755 root root -"
      "d ${cfg.stateDir}/certs 0755 root root -"
    ];

    environment.systemPackages = [ tools ];

    systemd.services.pd-openvpn-leaf-init = lib.mkIf cfg.autoGenerate {
      description = "Generate the local OpenVPN keypair and CSR";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${tools}/bin/pd-openvpn-leaf-init";
      };
    };
  };
}
