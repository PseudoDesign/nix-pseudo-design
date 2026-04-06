{ config, lib, ... }:
let
  cfg = config.services.pdOpenvpnServer;

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

  # This module intentionally consumes externally managed PKI material rather
  # than minting certificates itself.
  openvpnConfig =
    let
      # Build the generated OpenVPN config one directive per list element so
      # optional lines are easy to append and the final text stays readable.
      baseLines = [
        # Listener and tunnel interface setup.
        "port ${toString cfg.port}"
        "proto ${cfg.proto}"
        "dev ${cfg.dev}"
        "topology ${cfg.topology}"
        "server ${cfg.vpnSubnet} ${cfg.vpnNetmask}"

        # Server mode and connection liveness.
        "tls-server"
        "keepalive ${toString cfg.keepaliveInterval} ${toString cfg.keepaliveTimeout}"
        "persist-key"
        "persist-tun"

        # Modern data-channel and TLS requirements.
        "data-ciphers ${lib.concatStringsSep ":" cfg.dataCiphers}"
        "tls-version-min ${cfg.tlsVersionMin}"
        "dh none"

        # PKI material supplied by an external certificate authority workflow.
        "ca ${cfg.caCertFile}"
        "cert ${cfg.serverCertFile}"
        "key ${cfg.serverKeyFile}"
        "tls-crypt ${cfg.tlsCryptKeyFile}"
        "verify-client-cert require"

        # Runtime state written outside the Nix store for observability.
        "ifconfig-pool-persist ${cfg.ifconfigPoolPersistFile}"
        "status ${cfg.statusFile}"
        "status-version ${toString cfg.statusVersion}"
        "verb ${toString cfg.verb}"
      ]
      ++ lib.optional (cfg.crlFile != null) "crl-verify ${cfg.crlFile}"
      ++ lib.optional (cfg.clientConfigDir != null) "client-config-dir ${cfg.clientConfigDir}";
    in
    # OpenVPN expects a newline-delimited config file, so join the directives
    # here and append any caller-provided raw config at the end.
    lib.concatStringsSep "\n" baseLines + lib.optionalString (cfg.extraConfig != "") "\n${cfg.extraConfig}";
in
{
  options.services.pdOpenvpnServer = {
    enable = lib.mkEnableOption "pseudo.design OpenVPN server";

    instanceName = lib.mkOption {
      type = lib.types.str;
      default = "pd";
      description = "OpenVPN instance name exposed through services.openvpn.servers.<name>.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 1194;
      description = "OpenVPN listener port.";
    };

    proto = lib.mkOption {
      type = lib.types.str;
      default = "udp";
      description = "OpenVPN transport protocol.";
    };

    dev = lib.mkOption {
      type = lib.types.str;
      default = "tun0";
      description = "Tunnel device name created by OpenVPN.";
    };

    topology = lib.mkOption {
      type = lib.types.enum [ "subnet" ];
      default = "subnet";
      description = "Tunnel address topology.";
    };

    vpnSubnet = lib.mkOption {
      type = lib.types.str;
      example = "10.8.0.0";
      description = "IPv4 subnet handed out to VPN clients.";
    };

    vpnNetmask = lib.mkOption {
      type = lib.types.str;
      default = "255.255.255.0";
      description = "Netmask paired with vpnSubnet for the OpenVPN server directive.";
    };

    pki.bundleDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/openvpn/bundles";
      description = "Optional pd-ca workspace bundles directory used to derive caCertFile and crlFile defaults.";
    };

    pki.identityDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/openvpn/issued/openvpn/servers/server";
      description = "Optional pd-ca issued identity directory used to derive serverCertFile and serverKeyFile defaults.";
    };

    pki.identityName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "server";
      description = "Optional certificate basename inside pki.identityDir. Defaults to the identityDir basename.";
    };

    caCertFile = lib.mkOption {
      type = lib.types.str;
      example = "/run/secrets/openvpn/ca.crt";
      description = "CA certificate used to verify client certificates.";
    };

    serverCertFile = lib.mkOption {
      type = lib.types.str;
      example = "/run/secrets/openvpn/server.crt";
      description = "Server certificate presented to VPN clients.";
    };

    serverKeyFile = lib.mkOption {
      type = lib.types.str;
      example = "/run/secrets/openvpn/server.key";
      description = "Private key matching serverCertFile.";
    };

    tlsCryptKeyFile = lib.mkOption {
      type = lib.types.str;
      example = "/run/secrets/openvpn/tls-crypt.key";
      description = "Shared tls-crypt key distributed out of band.";
    };

    crlFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/openvpn/ca.crl.pem";
      description = "Optional certificate revocation list used to reject revoked client certificates.";
    };

    clientConfigDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/etc/openvpn/ccd";
      description = "Optional client-config-dir used for per-client address assignments.";
    };

    runtimeDir = lib.mkOption {
      type = lib.types.str;
      default = "/run/pd-openvpn/${cfg.instanceName}";
      description = "Directory for generated OpenVPN runtime files such as status and pool state.";
    };

    ifconfigPoolPersistFile = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.runtimeDir}/ipp.txt";
      description = "Path used by ifconfig-pool-persist.";
    };

    statusFile = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.runtimeDir}/status.log";
      description = "OpenVPN status output used for diagnostics and tests.";
    };

    statusVersion = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2;
      description = "status-version value written alongside statusFile.";
    };

    keepaliveInterval = lib.mkOption {
      type = lib.types.ints.positive;
      default = 10;
      description = "OpenVPN keepalive ping interval in seconds.";
    };

    keepaliveTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 60;
      description = "OpenVPN keepalive restart timeout in seconds.";
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

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to open the configured OpenVPN listener port in the firewall.";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra OpenVPN server directives appended verbatim to the generated config.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = cfg.pki.identityName == null || cfg.pki.identityDir != null;
            message = "services.pdOpenvpnServer.pki.identityName requires services.pdOpenvpnServer.pki.identityDir.";
          }
        ];

        networking.firewall.allowedUDPPorts = lib.optional (cfg.openFirewall && lib.hasPrefix "udp" cfg.proto) cfg.port;
        networking.firewall.allowedTCPPorts = lib.optional (cfg.openFirewall && lib.hasPrefix "tcp" cfg.proto) cfg.port;

        systemd.tmpfiles.rules = [ "d ${cfg.runtimeDir} 0750 root root -" ];

        services.openvpn.servers.${cfg.instanceName}.config = openvpnConfig;
      }

      (lib.mkIf (cfg.pki.bundleDir != null) {
        services.pdOpenvpnServer.caCertFile = lib.mkDefault "${cfg.pki.bundleDir}/openvpn-ca.crt";
        services.pdOpenvpnServer.crlFile = lib.mkDefault "${cfg.pki.bundleDir}/openvpn-ca.crl.pem";
      })

      (lib.mkIf (cfg.pki.identityDir != null && pkiIdentityName != null) {
        services.pdOpenvpnServer.serverCertFile = lib.mkDefault "${cfg.pki.identityDir}/${pkiIdentityName}.crt";
        services.pdOpenvpnServer.serverKeyFile = lib.mkDefault "${cfg.pki.identityDir}/${pkiIdentityName}.key";
      })
    ]
  );
}
