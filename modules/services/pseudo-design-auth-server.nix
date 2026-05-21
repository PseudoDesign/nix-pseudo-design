{
  config,
  lib,
  pdPki,
  pkgs,
  ...
}:

let
  cfg = config.services.pseudoDesign.authServer;
  inherit (lib)
    escapeShellArg
    mkEnableOption
    mkForce
    mkIf
    mkOption
    optional
    optionalAttrs
    optionalString
    types
    ;

  pdPkiIntermediateStateDirArg = escapeShellArg cfg.pdPkiIntermediateStateDir;
  pdPkiSigningTools = pdPki.packages.${pkgs.stdenv.hostPlatform.system}.pd-pki-signing-tools;
  rootCertificateInstallService = "pseudo-design-step-ca-root-cert.service";
  stepCaConfigService = "pseudo-design-step-ca-config.service";
  pdPkiIntermediateInitService = "pd-pki-intermediate-signing-authority-init.service";
  pdPkiIntermediateAccessService = "pseudo-design-step-ca-intermediate-access.service";
  pdPkiIntermediateParentDir = builtins.dirOf cfg.pdPkiIntermediateStateDir;
  pdPkiBaseStateDir = builtins.dirOf pdPkiIntermediateParentDir;
  pdPkiIntermediateParentDirArg = escapeShellArg pdPkiIntermediateParentDir;
  pdPkiBaseStateDirArg = escapeShellArg pdPkiBaseStateDir;
  pdPkiIntermediateKeyFileArg = escapeShellArg cfg.intermediateKeyFile;
  pdPkiIntermediateCsrFileArg = escapeShellArg "${cfg.pdPkiIntermediateStateDir}/intermediate-ca.csr.pem";
  pdPkiIntermediateRequestFileArg = escapeShellArg "${cfg.pdPkiIntermediateStateDir}/signing-request.json";
  pdPkiIntermediateCertFileArg = escapeShellArg cfg.intermediateCertificateFile;
  pdPkiIntermediateChainFileArg = escapeShellArg "${cfg.pdPkiIntermediateStateDir}/chain.pem";
  pdPkiIntermediateCrlFileArg = escapeShellArg "${cfg.pdPkiIntermediateStateDir}/crl.pem";
  pdPkiIntermediateMetadataFileArg = escapeShellArg "${cfg.pdPkiIntermediateStateDir}/signer-metadata.json";
  runtimeCaConfigFile = "/run/pseudo-design-step-ca/ca.json";
  usesRuntimeEnrollmentProvisioner = cfg.enrollmentProvisionerPublicKeyFile != null;
  usesStaticEnrollmentProvisioner = cfg.enrollmentProvisionerPublicKey != null;

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

  deviceLeafTemplateFile = pkgs.writeText "pseudo-design-device-leaf-template.json" deviceLeafTemplate;

  mkEnrollmentProvisioner = key: {
    type = "JWK";
    name = cfg.enrollmentProvisionerName;
    inherit key;
    claims = {
      minTLSCertDuration = "5m";
      maxTLSCertDuration = cfg.leafDuration;
      defaultTLSCertDuration = cfg.leafDuration;
      disableRenewal = false;
    };
    options.x509.template = deviceLeafTemplate;
  };

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

  fixPdPkiIntermediateAccess = ''
    for dir in ${pdPkiBaseStateDirArg} ${pdPkiIntermediateParentDirArg}; do
      if [ -d "$dir" ]; then
        chown root:root "$dir"
        chmod 0755 "$dir"
      fi
    done

    if [ -d ${pdPkiIntermediateStateDirArg} ]; then
      chown root:step-ca ${pdPkiIntermediateStateDirArg}
      chmod 0750 ${pdPkiIntermediateStateDirArg}
    fi

    if [ -e ${pdPkiIntermediateKeyFileArg} ]; then
      chown root:step-ca ${pdPkiIntermediateKeyFileArg}
      chmod 0640 ${pdPkiIntermediateKeyFileArg}
    fi

    for path in \
      ${pdPkiIntermediateCsrFileArg} \
      ${pdPkiIntermediateRequestFileArg} \
      ${pdPkiIntermediateCertFileArg} \
      ${pdPkiIntermediateChainFileArg} \
      ${pdPkiIntermediateCrlFileArg} \
      ${pdPkiIntermediateMetadataFileArg}; do
      if [ -e "$path" ]; then
        chown root:step-ca "$path"
        chmod 0644 "$path"
      fi
    done
  '';

  caExportIntermediateRequest = pkgs.writeShellApplication {
    name = "pseudo-design-ca-export-intermediate-request";
    runtimeInputs = [
      pkgs.coreutils
      pdPkiSigningTools
    ];
    text = ''
      if [ "''${1:-}" = "-h" ] || [ "''${1:-}" = "--help" ]; then
        printf 'Usage: sudo pseudo-design-ca-export-intermediate-request OUT_DIR\n'
        exit 0
      fi

      if [ "$#" -ne 1 ]; then
        printf 'Usage: sudo pseudo-design-ca-export-intermediate-request OUT_DIR\n' >&2
        exit 2
      fi

      ${requireRoot}

      systemctl start ${pdPkiIntermediateInitService}
      systemctl start ${pdPkiIntermediateAccessService}
      exec pd-pki-signing-tools export-request \
        --role intermediate-signing-authority \
        --state-dir ${pdPkiIntermediateStateDirArg} \
        --out-dir "$1"
    '';
  };

  caImportSignedIntermediate = pkgs.writeShellApplication {
    name = "pseudo-design-ca-import-signed-intermediate";
    runtimeInputs = [
      pkgs.coreutils
      pdPkiSigningTools
    ];
    text = ''
      if [ "''${1:-}" = "-h" ] || [ "''${1:-}" = "--help" ]; then
        printf 'Usage: sudo pseudo-design-ca-import-signed-intermediate SIGNED_DIR\n'
        exit 0
      fi

      if [ "$#" -ne 1 ]; then
        printf 'Usage: sudo pseudo-design-ca-import-signed-intermediate SIGNED_DIR\n' >&2
        exit 2
      fi

      ${requireRoot}

      pd-pki-signing-tools import-signed \
        --role intermediate-signing-authority \
        --state-dir ${pdPkiIntermediateStateDirArg} \
        --signed-dir "$1"

      ${fixPdPkiIntermediateAccess}
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
      default = "${cfg.pdPkiIntermediateStateDir}/intermediate-ca.cert.pem";
      description = "Path to the online intermediate CA certificate.";
    };

    intermediateKeyFile = mkOption {
      type = types.str;
      default = "${cfg.pdPkiIntermediateStateDir}/intermediate-ca.key.pem";
      description = "Path to the online intermediate CA private key.";
    };

    pdPkiIntermediateStateDir = mkOption {
      type = types.str;
      default = "/var/lib/pd-pki/authorities/intermediate";
      description = "pd-pki runtime state directory for the online intermediate CA.";
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

    enrollmentProvisionerPublicKeyFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Runtime path to the public JWK for the one-time enrollment provisioner.";
    };

    leafDuration = mkOption {
      type = types.str;
      default = "24h";
      description = "Default and maximum duration for device client certificates.";
    };

    enableAcme = mkOption {
      type = types.bool;
      default = true;
      description = "Whether the auth gateway nginx vhost should request a public ACME certificate.";
    };

    authTlsCertificateFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Runtime TLS certificate or fullchain used by the auth gateway when enableAcme is false.";
    };

    authTlsKeyFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Runtime TLS private key used by the auth gateway when enableAcme is false.";
    };

    authUpstream = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "http://127.0.0.1:8080";
      description = "Optional upstream protected by auth.pseudo.design mTLS.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !(usesStaticEnrollmentProvisioner && usesRuntimeEnrollmentProvisioner);
        message = "services.pseudoDesign.authServer.enrollmentProvisionerPublicKey and enrollmentProvisionerPublicKeyFile are mutually exclusive.";
      }
      {
        assertion = cfg.enableAcme || (cfg.authTlsCertificateFile != null && cfg.authTlsKeyFile != null);
        message = "services.pseudoDesign.authServer.authTlsCertificateFile and authTlsKeyFile must be set when enableAcme is false.";
      }
    ];

    warnings = optional (!usesStaticEnrollmentProvisioner && !usesRuntimeEnrollmentProvisioner) ''
      services.pseudoDesign.authServer is enabled without
      enrollmentProvisionerPublicKey or enrollmentProvisionerPublicKeyFile.
      One-time device enrollment tokens cannot be validated until the public JWK
      is configured.
    '';

    environment.systemPackages = [
      pkgs.step-cli
      pdPkiSigningTools
      caExportIntermediateRequest
      caImportSignedIntermediate
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.caStateDir}/certs 0750 step-ca step-ca -"
      "d ${cfg.caStateDir}/secrets 0750 step-ca step-ca -"
      "d ${cfg.authStateDir} 0755 root root -"
      "f ${cfg.nginxDenylistFile} 0644 root root -"
    ]
    ++ optional usesRuntimeEnrollmentProvisioner "d /run/pseudo-design-step-ca 0755 root root -";

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
          provisioners = optional usesStaticEnrollmentProvisioner (
            mkEnrollmentProvisioner cfg.enrollmentProvisionerPublicKey
          );
        };
      };
    };

    systemd.services.step-ca = {
      unitConfig.ConditionPathExists = [
        cfg.rootCertificateFile
        cfg.intermediateCertificateFile
        cfg.intermediateKeyFile
      ]
      ++ optional usesRuntimeEnrollmentProvisioner cfg.enrollmentProvisionerPublicKeyFile;
      after = [
        pdPkiIntermediateInitService
        pdPkiIntermediateAccessService
      ]
      ++ optional (cfg.rootCertificateSourceFile != null) rootCertificateInstallService
      ++ optional usesRuntimeEnrollmentProvisioner stepCaConfigService;
      wants = [
        pdPkiIntermediateInitService
        pdPkiIntermediateAccessService
      ]
      ++ optional (cfg.rootCertificateSourceFile != null) rootCertificateInstallService
      ++ optional usesRuntimeEnrollmentProvisioner stepCaConfigService;
      serviceConfig.ExecStart = mkIf usesRuntimeEnrollmentProvisioner (mkForce [
        ""
        (
          "${config.services.step-ca.package}/bin/step-ca ${runtimeCaConfigFile}"
          + optionalString (
            cfg.intermediatePasswordFile != null
          ) " --password-file \${CREDENTIALS_DIRECTORY}/intermediate_password"
        )
      ]);
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

    systemd.services.pseudo-design-step-ca-intermediate-access = {
      description = "Grant step-ca access to pd-pki intermediate runtime files";
      before = [ "step-ca.service" ];
      after = [
        "systemd-tmpfiles-setup.service"
        pdPkiIntermediateInitService
      ];
      path = [ pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = fixPdPkiIntermediateAccess;
    };

    systemd.services.pseudo-design-step-ca-config = mkIf usesRuntimeEnrollmentProvisioner {
      description = "Render pseudo.design step-ca runtime configuration";
      before = [ "step-ca.service" ];
      after = [ "systemd-tmpfiles-setup.service" ];
      unitConfig.ConditionPathExists = cfg.enrollmentProvisionerPublicKeyFile;
      serviceConfig.Type = "oneshot";
      script = ''
        ${pkgs.coreutils}/bin/install -d -m 0755 /run/pseudo-design-step-ca
        ${pkgs.jq}/bin/jq \
          --slurpfile key ${escapeShellArg cfg.enrollmentProvisionerPublicKeyFile} \
          --rawfile template ${deviceLeafTemplateFile} \
          --arg name ${escapeShellArg cfg.enrollmentProvisionerName} \
          --arg leafDuration ${escapeShellArg cfg.leafDuration} \
          '.authority.provisioners = [
            {
              type: "JWK",
              name: $name,
              key: $key[0],
              claims: {
                minTLSCertDuration: "5m",
                maxTLSCertDuration: $leafDuration,
                defaultTLSCertDuration: $leafDuration,
                disableRenewal: false
              },
              options: {
                x509: {
                  template: $template
                }
              }
            }
          ]' \
          /etc/smallstep/ca.json > ${runtimeCaConfigFile}.tmp
        ${pkgs.coreutils}/bin/install -o step-ca -g step-ca -m 0644 \
          ${runtimeCaConfigFile}.tmp \
          ${runtimeCaConfigFile}
        ${pkgs.coreutils}/bin/rm -f ${runtimeCaConfigFile}.tmp
      '';
    };

    systemd.services.pseudo-design-auth-ca-bundle = {
      description = "Install pseudo.design device root CA bundle for nginx";
      wantedBy = [ "multi-user.target" ];
      before = [ "nginx.service" ];
      after = optional (cfg.rootCertificateSourceFile != null) rootCertificateInstallService;
      wants = optional (cfg.rootCertificateSourceFile != null) rootCertificateInstallService;
      unitConfig.ConditionPathExists = [
        cfg.rootCertificateFile
        cfg.intermediateCertificateFile
      ];
      serviceConfig.Type = "oneshot";
      script = ''
        ${pkgs.coreutils}/bin/cat \
          ${cfg.rootCertificateFile} \
          ${cfg.intermediateCertificateFile} \
          > ${cfg.nginxClientCaFile}.tmp
        ${pkgs.coreutils}/bin/install -D -m 0644 ${cfg.nginxClientCaFile}.tmp \
          ${cfg.nginxClientCaFile}
        ${pkgs.coreutils}/bin/rm -f ${cfg.nginxClientCaFile}.tmp
      '';
    };

    systemd.services.nginx = {
      after = [ "pseudo-design-auth-ca-bundle.service" ];
      wants = [ "pseudo-design-auth-ca-bundle.service" ];
      unitConfig =
        optionalAttrs (!cfg.enableAcme && cfg.authTlsCertificateFile != null && cfg.authTlsKeyFile != null)
          {
            ConditionPathExists = [
              cfg.authTlsCertificateFile
              cfg.authTlsKeyFile
            ];
          };
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
        enableACME = cfg.enableAcme;
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

        locations = {
          "@pseudo_design_client_cert_error".return = "403";

          "/" = {
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
      }
      //
        optionalAttrs (!cfg.enableAcme && cfg.authTlsCertificateFile != null && cfg.authTlsKeyFile != null)
          {
            sslCertificate = cfg.authTlsCertificateFile;
            sslCertificateKey = cfg.authTlsKeyFile;
          };
    };
  };
}
