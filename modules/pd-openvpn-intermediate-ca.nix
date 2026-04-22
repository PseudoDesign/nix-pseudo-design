{ config, lib, pkgs, ... }:
let
  cfg = config.services.pdOpenvpnIntermediateCA;
  tools = pkgs.callPackage ../packages/pd-openvpn-intermediate-ca.nix {
    inherit
      (cfg)
      digest
      keyBits
      leafDays
      passphraseFile
      stateDir
      subject
      ;
  };
in
{
  options.services.pdOpenvpnIntermediateCA = {
    enable = lib.mkEnableOption "offline intermediate CA tooling for OpenVPN server and client certificates";

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/pd-openvpn/intermediate-ca";
      description = "Runtime state directory used for the intermediate CA key, CSR, certificates, database, and staging folders.";
    };

    subject = lib.mkOption {
      type = lib.types.str;
      default = "/CN=Pseudo Design OpenVPN Intermediate CA";
      description = "OpenSSL subject used when creating the intermediate CA CSR.";
    };

    passphraseFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional runtime path to a file containing the intermediate CA key passphrase.";
    };

    keyBits = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4096;
      description = "RSA key size used when generating the intermediate CA private key.";
    };

    digest = lib.mkOption {
      type = lib.types.str;
      default = "sha256";
      description = "Message digest used by the intermediate CA when signing server and client certificates.";
    };

    leafDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 825;
      description = "Validity period in days for server and client certificates signed by the intermediate.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0700 root root -"
      "d ${cfg.stateDir}/private 0700 root root -"
      "d ${cfg.stateDir}/certs 0755 root root -"
      "d ${cfg.stateDir}/csr 0755 root root -"
      "d ${cfg.stateDir}/incoming 0755 root root -"
      "d ${cfg.stateDir}/issued 0755 root root -"
      "d ${cfg.stateDir}/issued/servers 0755 root root -"
      "d ${cfg.stateDir}/issued/clients 0755 root root -"
      "d ${cfg.stateDir}/newcerts 0755 root root -"
    ];

    environment.systemPackages = [ tools ];
  };
}
