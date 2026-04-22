{ config, lib, pkgs, ... }:
let
  cfg = config.services.pdOpenvpnRootCA;
  tools = pkgs.callPackage ../packages/pd-openvpn-root-ca.nix {
    inherit
      (cfg)
      certificateDays
      digest
      intermediateDays
      keyBits
      passphraseFile
      pathLen
      stateDir
      subject
      ;
  };
in
{
  options.services.pdOpenvpnRootCA = {
    enable = lib.mkEnableOption "offline root CA tooling for signing OpenVPN intermediate CAs";

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/pd-openvpn/root-ca";
      description = "Runtime state directory used for the root CA private key, certificate, database, and staging folders.";
    };

    subject = lib.mkOption {
      type = lib.types.str;
      default = "/CN=Pseudo Design OpenVPN Root CA";
      description = "OpenSSL subject used when creating the self-signed root CA certificate.";
    };

    passphraseFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional runtime path to a file containing the root CA key passphrase.";
    };

    keyBits = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4096;
      description = "RSA key size used when generating the root CA private key.";
    };

    digest = lib.mkOption {
      type = lib.types.str;
      default = "sha256";
      description = "Message digest used by the root CA when signing certificates.";
    };

    certificateDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 7300;
      description = "Validity period in days for the self-signed root CA certificate.";
    };

    intermediateDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3650;
      description = "Validity period in days for intermediate CA certificates signed by this root.";
    };

    pathLen = lib.mkOption {
      type = lib.types.ints.between 0 8;
      default = 1;
      description = "Maximum subordinate CA path length advertised by the root CA certificate.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0700 root root -"
      "d ${cfg.stateDir}/private 0700 root root -"
      "d ${cfg.stateDir}/certs 0755 root root -"
      "d ${cfg.stateDir}/incoming 0755 root root -"
      "d ${cfg.stateDir}/incoming/intermediates 0755 root root -"
      "d ${cfg.stateDir}/issued 0755 root root -"
      "d ${cfg.stateDir}/issued/intermediates 0755 root root -"
      "d ${cfg.stateDir}/newcerts 0755 root root -"
    ];

    environment.systemPackages = [ tools ];
  };
}
