{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.pseudoDesign.authServer;
  inherit (lib) escapeShellArg mkEnableOption mkIf mkOption optional optionalString types;

  caTools = pkgs.callPackage ../../packages/pseudo-design-ca-tools { };
  caStateDirArg = escapeShellArg cfg.caStateDir;
  rootCertificateInstallService = "pseudo-design-step-ca-root-cert.service";

  deviceLeafTemplate = ''
    {
      "subject": {
        "commonName": {{ toJson .Subject.CommonName }}
      },
      "sans": {{ toJson .SANs }},
      "keyUsage": ["digitalSignature"],
      "extKeyUsage": ["clientAuth"]
    }
  '';

  identityHeaders = ''
    proxy_set_header X-Pseudo-Design-Client-Verify $ssl_client_verify;
    proxy_set_header X-Pseudo-Design-Client-Subject $ssl_client_s_dn;
    proxy_set_header X-Pseudo-Design-Client-Serial $ssl_client_serial;
    proxy_set_header X-Pseudo-Design-Client-Fingerprint $ssl_client_fingerprint;
    proxy_set_header X-Pseudo-Design-Client-Cert $ssl_client_escaped_cert;
  '';

  requireRoot = ''
    if [ "$(${pkgs.coreutils}/bin/id -u)" -ne 0 ]; then
      printf 'error: run this command with sudo\n' >&2
      exit 1
    fi
  '';

  caCreateIntermediateCsr = pkgs.writeShellApplication {
    name = "pseudo-design-ca-create-intermediate-csr";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.step-cli
    ];
    text = ''
      if [ "''${1:-}" = "-h" ] || [ "''${1:-}" = "--help" ]; then
        printf 'Usage: sudo pseudo-design-ca-create-intermediate-csr\n'
        exit 0
      fi

      if [ "$#" -ne 0 ]; then
        printf 'Usage: sudo pseudo-design-ca-create-intermediate-csr\n' >&2
        exit 2
      fi

      ${requireRoot}

      export PSEUDO_DESIGN_STEP_CA_OWNER=step-ca:step-ca
      exec ${caTools}/libexec/pseudo-design-ca/create-intermediate-csr.sh ${caStateDirArg}
    '';
  };

  caInstallIntermediateCert = pkgs.writeShellApplication {
    name = "pseudo-design-ca-install-intermediate-cert";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.openssl
    ];
    text = ''
      if [ "''${1:-}" = "-h" ] || [ "''${1:-}" = "--help" ]; then
        printf 'Usage: sudo pseudo-design-ca-install-intermediate-cert CERT\n'
        exit 0
      fi

      if [ "$#" -ne 1 ]; then
        printf 'Usage: sudo pseudo-design-ca-install-intermediate-cert CERT\n' >&2
        exit 2
      fi

      ${requireRoot}

      export PSEUDO_DESIGN_STEP_CA_OWNER=step-ca:step-ca
      exec ${caTools}/libexec/pseudo-design-ca/install-intermediate-cert.sh "$1" ${caStateDirArg}
    '';
  };
in
{
  options.services.pseudoDesign.authServer = {
    enable = mkEnableOption "the pseudo.design CA and mTLS auth gateway";

    domain = mkOption {
      type = types.str;
      default = "pseudo.design";
      description = "Base domain for the pseudo.design identity endpoints.";
    };

    caHost = mkOption {
      type = types.str;
      default = "ca.${cfg.domain}";
      description = "DNS name used by devices to reach step-ca.";
    };

    authHost = mkOption {
      type = types.str;
      default = "auth.${cfg.domain}";
      description = "DNS name for the nginx mTLS-protected endpoint.";
    };

    caAddress = mkOption {
      type = types.str;
      default = "[::]";
      description = "Address for step-ca to listen on.";
    };

    caPort = mkOption {
      type = types.port;
      default = 8443;
      description = "Public TCP port for step-ca.";
    };

    caStateDir = mkOption {
      type = types.str;
      default = "/var/lib/step-ca";
      description = "Runtime state directory containing step-ca certificates, keys, and database.";
    };

    intermediatePasswordFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional runtime-only path containing the password for an encrypted intermediate CA key.";
    };

    rootCertificateFile = mkOption {
      type = types.str;
      default = "${cfg.caStateDir}/certs/root_ca.crt";
      description = "Path to the public root CA certificate used by step-ca.";
    };

    rootCertificateSourceFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Optional public root CA certificate source to install into rootCertificateFile.";
    };

    intermediateCertificateFile = mkOption {
      type = types.str;
      default = "${cfg.caStateDir}/certs/intermediate_ca.crt";
      description = "Path to the online intermediate CA certificate.";
    };

    intermediateKeyFile = mkOption {
      type = types.str;
      default = "${cfg.caStateDir}/secrets/intermediate_ca.key";
      description = "Path to the online intermediate CA private key.";
    };

    authStateDir = mkOption {
      type = types.str;
      default = "/var/lib/pseudo-design/auth";
      description = "State directory for nginx auth gateway trust and denylist files.";
    };

    nginxClientCaFile = mkOption {
      type = types.str;
      default = "${cfg.authStateDir}/device-root-ca.crt";
      description = "Root CA bundle path read by nginx for client certificate verification.";
    };

    nginxDenylistFile = mkOption {
      type = types.str;
      default = "${cfg.authStateDir}/deny-fingerprints.map";
      description = "Nginx map fragment of denied client certificate fingerprints.";
    };

    enrollmentProvisionerName = mkOption {
      type = types.str;
      default = "device-enrollment";
      description = "step-ca JWK provisioner name used for one-time device enrollment tokens.";
    };

    enrollmentProvisionerPublicKey = mkOption {
      type = types.nullOr (types.attrsOf types.anything);
      default = null;
      description = "Public JWK for the one-time enrollment provisioner. Keep the private JWK out of Git.";
    };

    leafDuration = mkOption {
      type = types.str;
      default = "24h";
      description = "Default and maximum duration for device client certificates.";
    };

    authUpstream = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "http://127.0.0.1:8080";
      description = "Optional upstream protected by auth.pseudo.design mTLS.";
    };
  };

  config = mkIf cfg.enable {
    warnings = optional (cfg.enrollmentProvisionerPublicKey == null) ''
      services.pseudoDesign.authServer is enabled without
      enrollmentProvisionerPublicKey. One-time device enrollment tokens cannot
      be validated until the public JWK is configured.
    '';

    environment.systemPackages = [
      pkgs.step-cli
      caCreateIntermediateCsr
      caInstallIntermediateCert
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.caStateDir}/certs 0750 step-ca step-ca -"
      "d ${cfg.caStateDir}/secrets 0750 step-ca step-ca -"
      "d ${cfg.authStateDir} 0755 root root -"
      "f ${cfg.nginxDenylistFile} 0644 root root -"
    ];

    services.step-ca = {
      enable = true;
      address = cfg.caAddress;
      port = cfg.caPort;
      openFirewall = true;
      intermediatePasswordFile = cfg.intermediatePasswordFile;
      settings = {
        dnsNames = [
          cfg.caHost
          config.networking.hostName
          "localhost"
        ];
        root = cfg.rootCertificateFile;
        crt = cfg.intermediateCertificateFile;
        key = cfg.intermediateKeyFile;
        db = {
          type = "badger";
          dataSource = "${cfg.caStateDir}/db";
        };
        authority = {
          claims = {
            minTLSCertDuration = "5m";
            maxTLSCertDuration = cfg.leafDuration;
            defaultTLSCertDuration = cfg.leafDuration;
            disableRenewal = false;
          };
          provisioners =
            optional (cfg.enrollmentProvisionerPublicKey != null)
              {
                type = "JWK";
                name = cfg.enrollmentProvisionerName;
                key = cfg.enrollmentProvisionerPublicKey;
                claims = {
                  minTLSCertDuration = "5m";
                  maxTLSCertDuration = cfg.leafDuration;
                  defaultTLSCertDuration = cfg.leafDuration;
                  disableRenewal = false;
                };
                options.x509.template = deviceLeafTemplate;
              };
        };
      };
    };

    systemd.services.step-ca = {
      unitConfig.ConditionPathExists = [
        cfg.rootCertificateFile
        cfg.intermediateCertificateFile
        cfg.intermediateKeyFile
      ];
      after = optional (cfg.rootCertificateSourceFile != null) rootCertificateInstallService;
      wants = optional (cfg.rootCertificateSourceFile != null) rootCertificateInstallService;
    };

    networking.firewall.allowedTCPPorts = [
      80
      443
      cfg.caPort
    ];

    systemd.services.pseudo-design-step-ca-root-cert = mkIf (cfg.rootCertificateSourceFile != null) {
      description = "Install pseudo.design root CA certificate for step-ca";
      wantedBy = [ "multi-user.target" ];
      before = [
        "step-ca.service"
        "pseudo-design-auth-ca-bundle.service"
      ];
      after = [ "systemd-tmpfiles-setup.service" ];
      serviceConfig.Type = "oneshot";
      script = ''
        ${pkgs.coreutils}/bin/install -D -o step-ca -g step-ca -m 0644 \
          ${cfg.rootCertificateSourceFile} \
          ${cfg.rootCertificateFile}
      '';
    };

    systemd.services.pseudo-design-auth-ca-bundle = {
      description = "Install pseudo.design device root CA bundle for nginx";
      wantedBy = [ "multi-user.target" ];
      before = [ "nginx.service" ];
      after = optional (cfg.rootCertificateSourceFile != null) rootCertificateInstallService;
      wants = optional (cfg.rootCertificateSourceFile != null) rootCertificateInstallService;
      unitConfig.ConditionPathExists = cfg.rootCertificateFile;
      serviceConfig.Type = "oneshot";
      script = ''
        ${pkgs.coreutils}/bin/install -D -m 0644 \
          ${cfg.rootCertificateFile} \
          ${cfg.nginxClientCaFile}
      '';
    };

    systemd.services.nginx = {
      after = [ "pseudo-design-auth-ca-bundle.service" ];
      wants = [ "pseudo-design-auth-ca-bundle.service" ];
    };

    services.nginx = {
      enable = true;
      recommendedProxySettings = true;

      commonHttpConfig = ''
        map $ssl_client_fingerprint $pseudo_design_client_blocked {
          default 0;
          include ${cfg.nginxDenylistFile};
        }
      '';

      virtualHosts.${cfg.authHost} = {
        enableACME = true;
        forceSSL = true;

        extraConfig = ''
          ssl_client_certificate ${cfg.nginxClientCaFile};
          ssl_verify_client on;
          ssl_verify_depth 2;
          error_page 495 496 =403 @pseudo_design_client_cert_error;

          if ($pseudo_design_client_blocked) {
            return 403;
          }

          add_header Strict-Transport-Security "max-age=31536000" always;
          add_header X-Content-Type-Options "nosniff" always;
          add_header Referrer-Policy "strict-origin-when-cross-origin" always;
          add_header X-Frame-Options "DENY" always;
        '';

        locations =
          {
            "@pseudo_design_client_cert_error".return = "403";

            "/" =
              {
                extraConfig =
                  identityHeaders
                  + optionalString (cfg.authUpstream == null) ''
                    default_type text/plain;
                    return 200 "authenticated\n";
                  '';
              }
              // lib.optionalAttrs (cfg.authUpstream != null) {
                proxyPass = cfg.authUpstream;
              };
          };
      };
    };
  };
}
