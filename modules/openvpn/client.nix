{ config, lib, pkgs, ... }:
let
  cfg = config.services.pdOpenvpnClient;
  installPkiExe = lib.getExe (pkgs.callPackage ../../packages/pki/pd-openvpn-install-pki.nix { });
  installServiceName = "pd-openvpn-client-${cfg.instanceName}-pki-install";

  pathBaseName =
    path:
    let
      segments = lib.filter (segment: segment != "") (lib.splitString "/" path);
    in
    if segments == [ ] then null else lib.last segments;

  pkiIdentityName =
    if cfg.pki.identityName != null then
      cfg.pki.identityName
    else if cfg.pki.identityDir != null then
      pathBaseName cfg.pki.identityDir
    else
      null;

  installedPkiIdentityName =
    if cfg.pki.identityName != null then
      cfg.pki.identityName
    else if cfg.pki.install.sourceDir != null then
      pathBaseName cfg.pki.install.sourceDir
    else
      null;

  # This module intentionally consumes externally managed PKI material rather
  # than minting certificates itself.
  openvpnConfig =
    let
      # Build the generated OpenVPN config one directive per list element so
      # optional lines are easy to append and the final text stays readable.
      baseLines = [
        # Client mode and remote server selection.
        "client"
        "dev ${cfg.dev}"
        "proto ${cfg.proto}"
        "remote ${cfg.remoteHost} ${toString cfg.remotePort}"
        "nobind"

        # Client liveness across restarts and reconnects.
        "tls-client"
        "persist-key"
        "persist-tun"

        # Modern data-channel and TLS requirements.
        "data-ciphers ${lib.concatStringsSep ":" cfg.dataCiphers}"
        "tls-version-min ${cfg.tlsVersionMin}"

        # PKI material supplied by an external certificate authority workflow.
        "ca ${cfg.caCertFile}"
        "cert ${cfg.clientCertFile}"
        "key ${cfg.clientKeyFile}"
        "tls-crypt ${cfg.tlsCryptKeyFile}"

        # Logging for troubleshooting and test visibility.
        "verb ${toString cfg.verb}"
      ]
      ++ lib.optional cfg.requireServerKeyUsage "remote-cert-tls server"
      ++ lib.optional (cfg.verifyX509Name != null) "verify-x509-name ${cfg.verifyX509Name} name";
    in
    # OpenVPN expects a newline-delimited config file, so join the directives
    # here and append any caller-provided raw config at the end.
    lib.concatStringsSep "\n" baseLines + lib.optionalString (cfg.extraConfig != "") "\n${cfg.extraConfig}";
in
{
  options.services.pdOpenvpnClient = {
    enable = lib.mkEnableOption "pseudo.design OpenVPN client";

    instanceName = lib.mkOption {
      type = lib.types.str;
      default = "pd";
      description = "OpenVPN instance name exposed through services.openvpn.servers.<name>.";
    };

    remoteHost = lib.mkOption {
      type = lib.types.str;
      example = "vpn.example.com";
      description = "OpenVPN server host or IP address.";
    };

    remotePort = lib.mkOption {
      type = lib.types.port;
      default = 1194;
      description = "OpenVPN server listener port.";
    };

    proto = lib.mkOption {
      type = lib.types.str;
      default = "udp";
      description = "OpenVPN transport protocol.";
    };

    dev = lib.mkOption {
      type = lib.types.str;
      default = "tun";
      description = "Tunnel device name requested by the client.";
    };

    pki.bundleDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/openvpn/bundles";
      description = "Optional pd-ca workspace bundles directory used to derive caCertFile defaults.";
    };

    pki.identityDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/openvpn/issued/openvpn/clients/laptop";
      description = "Optional pd-ca issued identity directory used to derive clientCertFile and clientKeyFile defaults.";
    };

    pki.identityName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "laptop";
      description = "Optional certificate basename inside pki.identityDir. Defaults to the identityDir basename.";
    };

    pki.install.sourceDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/var/lib/pseudo-design/stage/openvpn/adam-laptop";
      description = "Optional staged pd-ca tree copied into a writable runtime directory before OpenVPN starts.";
    };

    pki.install.targetDir = lib.mkOption {
      type = lib.types.str;
      default = "/run/secrets/openvpn/${cfg.instanceName}";
      example = "/run/secrets/openvpn/client";
      description = "Runtime directory where pki.install.sourceDir is installed.";
    };

    pki.install.tlsCryptSourceFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/var/lib/pseudo-design/openvpn/tls-crypt.key";
      description = "Optional tls-crypt key copied into pki.install.targetDir as tls-crypt.key before OpenVPN starts.";
    };

    caCertFile = lib.mkOption {
      type = lib.types.str;
      example = "/run/secrets/openvpn/ca.crt";
      description = "CA certificate used to verify the server certificate.";
    };

    clientCertFile = lib.mkOption {
      type = lib.types.str;
      example = "/run/secrets/openvpn/client.crt";
      description = "Client certificate presented to the OpenVPN server.";
    };

    clientKeyFile = lib.mkOption {
      type = lib.types.str;
      example = "/run/secrets/openvpn/client.key";
      description = "Private key matching clientCertFile.";
    };

    tlsCryptKeyFile = lib.mkOption {
      type = lib.types.str;
      example = "/run/secrets/openvpn/tls-crypt.key";
      description = "Shared tls-crypt key used by the OpenVPN control channel.";
    };

    requireServerKeyUsage = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Require the remote certificate to carry server authentication usage.";
    };

    verifyX509Name = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "vpn.example.com";
      description = "Optional exact certificate name to require from the remote server.";
    };

    dataCiphers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "AES-256-GCM"
        "AES-128-GCM"
      ];
      description = "Ordered list of data ciphers passed to data-ciphers.";
    };

    tlsVersionMin = lib.mkOption {
      type = lib.types.str;
      default = "1.2";
      description = "Minimum TLS version accepted for control-channel negotiation.";
    };

    verb = lib.mkOption {
      type = lib.types.ints.between 0 11;
      default = 3;
      description = "OpenVPN log verbosity.";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra OpenVPN client directives appended verbatim to the generated config.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = cfg.pki.identityName == null || cfg.pki.identityDir != null;
            message = "services.pdOpenvpnClient.pki.identityName requires services.pdOpenvpnClient.pki.identityDir.";
          }
          {
            assertion = cfg.pki.install.sourceDir == null || installedPkiIdentityName != null;
            message = "services.pdOpenvpnClient.pki.install.sourceDir requires an identity name that can be inferred from pki.identityName or the sourceDir basename.";
          }
          {
            assertion = cfg.pki.install.tlsCryptSourceFile == null || cfg.pki.install.sourceDir != null;
            message = "services.pdOpenvpnClient.pki.install.tlsCryptSourceFile requires services.pdOpenvpnClient.pki.install.sourceDir.";
          }
        ];

        services.openvpn.servers.${cfg.instanceName}.config = openvpnConfig;
      }

      (lib.mkIf (cfg.pki.bundleDir != null) {
        services.pdOpenvpnClient.caCertFile = lib.mkDefault "${cfg.pki.bundleDir}/openvpn-ca.crt";
      })

      (lib.mkIf (cfg.pki.identityDir != null && pkiIdentityName != null) {
        services.pdOpenvpnClient.clientCertFile = lib.mkDefault "${cfg.pki.identityDir}/${pkiIdentityName}.crt";
        services.pdOpenvpnClient.clientKeyFile = lib.mkDefault "${cfg.pki.identityDir}/${pkiIdentityName}.key";
      })

      (lib.mkIf (cfg.pki.install.sourceDir != null) {
        services.pdOpenvpnClient.pki.bundleDir = lib.mkDefault "${cfg.pki.install.targetDir}/bundles";
        services.pdOpenvpnClient.pki.identityDir = lib.mkDefault "${cfg.pki.install.targetDir}/issued/openvpn/clients/${installedPkiIdentityName}";

        systemd.services.${installServiceName} = {
          description = "Install staged OpenVPN client PKI material for ${cfg.instanceName}.";
          before = [ "openvpn-${cfg.instanceName}.service" ];
          serviceConfig = {
            Type = "oneshot";
          };
          script = ''
            '${installPkiExe}' \
              '${cfg.pki.install.sourceDir}' \
              '${cfg.pki.install.targetDir}'${lib.optionalString (cfg.pki.install.tlsCryptSourceFile != null) " \\\n              '${cfg.pki.install.tlsCryptSourceFile}'"}
          '';
        };

        systemd.services."openvpn-${cfg.instanceName}" = {
          requires = [ "${installServiceName}.service" ];
          after = [ "${installServiceName}.service" ];
        };
      })

      (lib.mkIf (cfg.pki.install.sourceDir != null && cfg.pki.install.tlsCryptSourceFile != null) {
        services.pdOpenvpnClient.tlsCryptKeyFile = lib.mkDefault "${cfg.pki.install.targetDir}/tls-crypt.key";
      })
    ]
  );
}
