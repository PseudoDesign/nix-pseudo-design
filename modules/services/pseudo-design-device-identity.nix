{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.pseudoDesign.deviceIdentity;
  inherit (lib) mkEnableOption mkIf mkOption optionalString types;

  subject = "device:${cfg.deviceName}";
  dnsName = "${cfg.deviceName}.devices.${cfg.domain}";
  uriName = "spiffe://${cfg.domain}/device/${cfg.deviceName}";
  step = lib.getExe cfg.package;
in
{
  options.services.pseudoDesign.deviceIdentity = {
    enable = mkEnableOption "pseudo.design device certificate enrollment and renewal";

    domain = mkOption {
      type = types.str;
      default = "pseudo.design";
      description = "Domain used for device certificate identities.";
    };

    deviceName = mkOption {
      type = types.str;
      default = config.networking.hostName;
      description = "Stable device name encoded into the certificate identity.";
    };

    caUrl = mkOption {
      type = types.str;
      default = "https://ca.${cfg.domain}:8443";
      description = "step-ca URL used for enrollment and renewal.";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/pseudo-design/device-identity";
      description = "Root-only state directory for device key, CSR, certificate, and CA trust.";
    };

    stepPath = mkOption {
      type = types.str;
      default = "${cfg.stateDir}/step";
      description = "STEPPATH used by step-cli on the device.";
    };

    privateKeyFile = mkOption {
      type = types.str;
      default = "${cfg.stateDir}/device.key";
      description = "Path to the device-unique TLS client private key.";
    };

    certificateFile = mkOption {
      type = types.str;
      default = "${cfg.stateDir}/device.crt";
      description = "Path to the issued TLS client certificate.";
    };

    csrFile = mkOption {
      type = types.str;
      default = "${cfg.stateDir}/device.csr";
      description = "Path used for the local certificate signing request.";
    };

    rootCertificateFile = mkOption {
      type = types.str;
      default = "${cfg.stateDir}/root_ca.crt";
      description = "Path to the CA root certificate trusted by step-cli.";
    };

    rootFingerprint = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional pinned root CA fingerprint. Public, but normally supplied after CA bootstrap.";
    };

    rootFingerprintFile = mkOption {
      type = types.str;
      default = "/run/keys/pseudo-design-ca-fingerprint";
      description = "Runtime path containing the pinned root CA fingerprint when rootFingerprint is unset.";
    };

    enrollmentTokenFile = mkOption {
      type = types.str;
      default = "/run/keys/pseudo-design-device-enrollment-token";
      description = "Runtime path containing a short-lived one-time enrollment token.";
    };

    leafDuration = mkOption {
      type = types.str;
      default = "24h";
      description = "Requested duration for enrolled device certificates.";
    };

    renewBefore = mkOption {
      type = types.str;
      default = "8h";
      description = "Renew when less than this much validity remains.";
    };

    renewCheckInterval = mkOption {
      type = types.str;
      default = "1h";
      description = "How often systemd checks whether the certificate needs renewal.";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.step-cli;
      description = "step-cli package used for enrollment and renewal.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
    services.timesyncd.enable = lib.mkDefault true;

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0700 root root -"
    ];

    systemd.services.pseudo-design-device-enroll = {
      description = "Enroll this host for a pseudo.design device certificate";
      wantedBy = [ "multi-user.target" ];
      wants = [
        "network-online.target"
        "time-sync.target"
      ];
      after = [
        "network-online.target"
        "time-sync.target"
      ];
      unitConfig.ConditionPathExists = [
        "!${cfg.certificateFile}"
        cfg.enrollmentTokenFile
      ];
      serviceConfig = {
        Type = "oneshot";
        UMask = "0077";
      };
      script = ''
        set -euo pipefail

        ${pkgs.coreutils}/bin/install -d -m 0700 ${cfg.stateDir}
        ${pkgs.coreutils}/bin/install -d -m 0700 ${cfg.stepPath}
        export STEPPATH=${cfg.stepPath}

        if [ ! -s ${cfg.rootCertificateFile} ]; then
          fingerprint="${optionalString (cfg.rootFingerprint != null) cfg.rootFingerprint}"
          if [ -z "$fingerprint" ] && [ -s ${cfg.rootFingerprintFile} ]; then
            fingerprint="$(${pkgs.coreutils}/bin/tr -d '[:space:]' < ${cfg.rootFingerprintFile})"
          fi

          if [ -z "$fingerprint" ]; then
            echo "Missing pseudo.design CA root fingerprint; refusing unauthenticated bootstrap." >&2
            exit 1
          fi

          ${step} ca bootstrap \
            --ca-url ${cfg.caUrl} \
            --fingerprint "$fingerprint" \
            --force

          ${pkgs.coreutils}/bin/install -m 0644 \
            ${cfg.stepPath}/certs/root_ca.crt \
            ${cfg.rootCertificateFile}
        fi

        if [ ! -s ${cfg.privateKeyFile} ]; then
          ${step} certificate create \
            ${lib.escapeShellArg subject} \
            ${cfg.csrFile} \
            ${cfg.privateKeyFile} \
            --csr \
            --kty EC \
            --curve P-256 \
            --no-password \
            --insecure \
            --san ${lib.escapeShellArg dnsName} \
            --san ${lib.escapeShellArg uriName} \
            --force
        else
          ${step} certificate create \
            --csr \
            --key ${cfg.privateKeyFile} \
            ${lib.escapeShellArg subject} \
            ${cfg.csrFile} \
            --san ${lib.escapeShellArg dnsName} \
            --san ${lib.escapeShellArg uriName} \
            --force
        fi

        token="$(${pkgs.coreutils}/bin/tr -d '[:space:]' < ${cfg.enrollmentTokenFile})"
        ${step} ca sign \
          ${cfg.csrFile} \
          ${cfg.certificateFile}.new \
          --token "$token" \
          --ca-url ${cfg.caUrl} \
          --root ${cfg.rootCertificateFile} \
          --not-after ${cfg.leafDuration} \
          --force

        ${pkgs.coreutils}/bin/chmod 0600 ${cfg.privateKeyFile}
        ${pkgs.coreutils}/bin/chmod 0644 ${cfg.certificateFile}.new ${cfg.rootCertificateFile}
        ${pkgs.coreutils}/bin/mv ${cfg.certificateFile}.new ${cfg.certificateFile}
        ${pkgs.coreutils}/bin/rm -f ${cfg.csrFile}
        ${pkgs.coreutils}/bin/rm -f ${cfg.enrollmentTokenFile} || true
      '';
    };

    systemd.services.pseudo-design-device-renew = {
      description = "Renew the pseudo.design device certificate";
      wants = [
        "network-online.target"
        "time-sync.target"
      ];
      after = [
        "network-online.target"
        "time-sync.target"
      ];
      unitConfig.ConditionPathExists = [
        cfg.certificateFile
        cfg.privateKeyFile
        cfg.rootCertificateFile
      ];
      serviceConfig = {
        Type = "oneshot";
        UMask = "0077";
      };
      script = ''
        set -euo pipefail
        export STEPPATH=${cfg.stepPath}

        if ! renew_output="$(
          ${step} ca renew \
            ${cfg.certificateFile} \
            ${cfg.privateKeyFile} \
            --ca-url ${cfg.caUrl} \
            --root ${cfg.rootCertificateFile} \
            --expires-in ${cfg.renewBefore} \
            --force 2>&1
        )"; then
          case "$renew_output" in
            *"certificate not renewed:"*)
              printf '%s\n' "$renew_output"
              exit 0
              ;;
            *)
              printf '%s\n' "$renew_output" >&2
              exit 1
              ;;
          esac
        fi
        printf '%s\n' "$renew_output"

        ${pkgs.coreutils}/bin/chmod 0600 ${cfg.privateKeyFile}
        ${pkgs.coreutils}/bin/chmod 0644 ${cfg.certificateFile}
      '';
    };

    systemd.timers.pseudo-design-device-renew = {
      description = "Check pseudo.design device certificate renewal";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "10m";
        OnUnitActiveSec = cfg.renewCheckInterval;
        RandomizedDelaySec = "15m";
        Persistent = true;
      };
    };
  };
}
