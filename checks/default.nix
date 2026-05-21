{
  nixpkgs,
  self,
  system,
}:

let
  lib = nixpkgs.lib;
  pkgs = import nixpkgs { inherit system; };
  caTools = self.packages.${system}.pseudo-design-ca-tools;

  enrollmentProvisionerPublicKey = {
    kty = "EC";
    use = "sig";
    crv = "P-256";
    kid = "test-device-enrollment";
    x = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
    y = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB";
  };

  mkConfig =
    modules:
    (lib.nixosSystem {
      inherit system;
      modules = modules ++ [
        {
          system.stateVersion = "25.11";
        }
      ];
    }).config;

  mkCheck =
    name: assertions:
    let
      checked = lib.foldl' (
        acc: assertion:
        assert lib.assertMsg assertion.condition "${name}: ${assertion.message}";
        acc
      ) true assertions;
    in
    assert checked;
    pkgs.runCommandLocal name { } ''
      touch "$out"
    '';

  hasInfix = lib.hasInfix;

  deviceConfig = mkConfig [
    self.nixosModules.pseudo-design-device-identity
    {
      networking.hostName = "ace";
      services.pseudoDesign.deviceIdentity = {
        enable = true;
        rootFingerprint = "test-root-fingerprint";
      };
    }
  ];

  deviceEnrollService = deviceConfig.systemd.services.pseudo-design-device-enroll;
  deviceRenewService = deviceConfig.systemd.services.pseudo-design-device-renew;
  deviceRenewTimer = deviceConfig.systemd.timers.pseudo-design-device-renew;
  deviceEnrollScript = deviceEnrollService.script;
  deviceRenewScript = deviceRenewService.script;

  authConfig = mkConfig [
    self.nixosModules.pseudo-design-auth-server
    {
      networking.hostName = "mako";

      security.acme = {
        acceptTerms = true;
        defaults.email = "admin@pseudo.design";
      };

      services.pseudoDesign.authServer = {
        enable = true;
        enrollmentProvisionerPublicKey = enrollmentProvisionerPublicKey;
        authUpstream = "http://127.0.0.1:8080";
        rootCertificateSourceFile = ../ca/public/README.md;
      };
    }
  ];

  authServer = authConfig.services.pseudoDesign.authServer;
  authPackageNames = map lib.getName authConfig.environment.systemPackages;
  rootCertService = authConfig.systemd.services.pseudo-design-step-ca-root-cert;
  authBundleService = authConfig.systemd.services.pseudo-design-auth-ca-bundle;
  stepCa = authConfig.services.step-ca;
  stepCaService = authConfig.systemd.services.step-ca;
  stepCaSettings = stepCa.settings;
  provisioner = builtins.head stepCaSettings.authority.provisioners;
  authVhost = authConfig.services.nginx.virtualHosts.${authServer.authHost};
  authLocation = authVhost.locations."/";

  runtimeEnrollmentProvisionerPublicKeyFile = "/var/lib/step-ca/certs/device-enrollment.pub.json";
  runtimeAuthTlsCertificateFile = "/var/lib/pseudo-design/auth/server.crt";
  runtimeAuthTlsKeyFile = "/var/lib/pseudo-design/auth/server.key";

  runtimeAuthConfig = mkConfig [
    self.nixosModules.pseudo-design-auth-server
    {
      networking.hostName = "intermediateca";

      services.pseudoDesign.authServer = {
        enable = true;
        domain = "test";
        caHost = "intermediateca";
        authHost = "intermediateca";
        enrollmentProvisionerPublicKeyFile = runtimeEnrollmentProvisionerPublicKeyFile;
        enableAcme = false;
        authTlsCertificateFile = runtimeAuthTlsCertificateFile;
        authTlsKeyFile = runtimeAuthTlsKeyFile;
      };
    }
  ];

  runtimeAuthServer = runtimeAuthConfig.services.pseudoDesign.authServer;
  runtimeStepCaSettings = runtimeAuthConfig.services.step-ca.settings;
  runtimeStepCaService = runtimeAuthConfig.systemd.services.step-ca;
  runtimeStepCaConfigService = runtimeAuthConfig.systemd.services.pseudo-design-step-ca-config;
  runtimeNginxService = runtimeAuthConfig.systemd.services.nginx;
  runtimeAuthVhost = runtimeAuthConfig.services.nginx.virtualHosts.${runtimeAuthServer.authHost};

  offlineCaConfig = mkConfig [
    self.nixosModules.pseudo-design-offline-ca
    {
      services.pseudoDesign.offlineCa.enable = true;
    }
  ];

  offlineCa = offlineCaConfig.services.pseudoDesign.offlineCa;
  offlineCaPackageNames = map lib.getName offlineCaConfig.environment.systemPackages;

  rootcaConfig = self.nixosConfigurations.rootca.config;
  rootcaBuild = rootcaConfig.system.build;
  rootcaBuildAttrNames = builtins.attrNames rootcaBuild;
in
{
  pseudo-design-device-identity-module = mkCheck "pseudo-design-device-identity-module" [
    {
      condition = deviceConfig.services.pseudoDesign.deviceIdentity.enable;
      message = "device identity module should be enabled";
    }
    {
      condition = lib.elem "d /var/lib/pseudo-design/device-identity 0700 root root -" deviceConfig.systemd.tmpfiles.rules;
      message = "device state directory should be root-only";
    }
    {
      condition = deviceEnrollService.serviceConfig.UMask == "0077";
      message = "enrollment service should use restrictive umask";
    }
    {
      condition = lib.elem "!/var/lib/pseudo-design/device-identity/device.crt" deviceEnrollService.unitConfig.ConditionPathExists;
      message = "enrollment should only run when the device cert is absent";
    }
    {
      condition = lib.elem "/run/keys/pseudo-design-device-enrollment-token" deviceEnrollService.unitConfig.ConditionPathExists;
      message = "enrollment should require the runtime one-time token";
    }
    {
      condition = hasInfix "fingerprint=\"test-root-fingerprint\"" deviceEnrollScript;
      message = "enrollment should pin the configured CA root fingerprint";
    }
    {
      condition = hasInfix "device:ace" deviceEnrollScript;
      message = "CSR subject should include the host device name";
    }
    {
      condition = hasInfix "--san ace.devices.pseudo.design" deviceEnrollScript;
      message = "CSR should include the device DNS SAN";
    }
    {
      condition = hasInfix "--san spiffe://pseudo.design/device/ace" deviceEnrollScript;
      message = "CSR should include the device SPIFFE URI SAN";
    }
    {
      condition = hasInfix "--not-after 24h" deviceEnrollScript;
      message = "enrollment should request a 24-hour certificate";
    }
    {
      condition = hasInfix "rm -f /run/keys/pseudo-design-device-enrollment-token" deviceEnrollScript;
      message = "enrollment should remove the one-time token after success";
    }
    {
      condition = deviceRenewTimer.timerConfig.OnUnitActiveSec == "1h";
      message = "renewal timer should check hourly";
    }
    {
      condition = deviceRenewTimer.timerConfig.RandomizedDelaySec == "15m";
      message = "renewal timer should use jitter";
    }
    {
      condition = hasInfix "--expires-in 8h" deviceRenewScript;
      message = "renewal should run when less than eight hours remain";
    }
    {
      condition = hasInfix "certificate not renewed:" deviceRenewScript;
      message = "renewal should treat early renewal as a successful no-op";
    }
  ];

  pseudo-design-auth-server-module = mkCheck "pseudo-design-auth-server-module" [
    {
      condition = stepCa.enable;
      message = "auth server should enable step-ca";
    }
    {
      condition = stepCa.port == 8443;
      message = "step-ca should listen on 8443";
    }
    {
      condition = stepCa.openFirewall;
      message = "step-ca firewall opening should be enabled";
    }
    {
      condition = stepCa.intermediatePasswordFile == null;
      message = "step-ca should not use an intermediate key password file";
    }
    {
      condition = lib.all (path: lib.elem path stepCaService.unitConfig.ConditionPathExists) [
        "/var/lib/step-ca/certs/root_ca.crt"
        "/var/lib/step-ca/certs/intermediate_ca.crt"
        "/var/lib/step-ca/secrets/intermediate_ca.key"
      ];
      message = "step-ca should require root, intermediate cert, and intermediate key files";
    }
    {
      condition =
        stepCaSettings.db == {
          type = "badger";
          dataSource = "/var/lib/step-ca/db";
        };
      message = "step-ca should use the configured badger database path";
    }
    {
      condition = stepCaSettings.authority.claims.defaultTLSCertDuration == "24h";
      message = "default TLS certificate duration should be 24 hours";
    }
    {
      condition = builtins.length stepCaSettings.authority.provisioners == 1;
      message = "a public enrollment JWK should create exactly one provisioner";
    }
    {
      condition = provisioner.type == "JWK";
      message = "enrollment provisioner should be JWK-backed";
    }
    {
      condition = provisioner.name == "device-enrollment";
      message = "enrollment provisioner should use the expected name";
    }
    {
      condition = provisioner.key == enrollmentProvisionerPublicKey;
      message = "enrollment provisioner should use the configured public JWK";
    }
    {
      condition = provisioner.claims.defaultTLSCertDuration == "24h";
      message = "provisioner should default device certs to 24 hours";
    }
    {
      condition = hasInfix ''"extKeyUsage": ["clientAuth"]'' provisioner.options.x509.template;
      message = "device leaf template should restrict EKU to clientAuth";
    }
    {
      condition = hasInfix ''"keyUsage": ["digitalSignature"]'' provisioner.options.x509.template;
      message = "device leaf template should restrict key usage to digitalSignature";
    }
    {
      condition = lib.all (port: lib.elem port authConfig.networking.firewall.allowedTCPPorts) [
        80
        443
        8443
      ];
      message = "auth server should open HTTP, HTTPS, and step-ca ports";
    }
    {
      condition = authVhost.enableACME && authVhost.forceSSL;
      message = "auth vhost should use public ACME server TLS and force HTTPS";
    }
    {
      condition = hasInfix "ssl_client_certificate /var/lib/pseudo-design/auth/device-root-ca.crt;" authVhost.extraConfig;
      message = "auth vhost should trust the device root CA bundle";
    }
    {
      condition = hasInfix "ssl_verify_client on;" authVhost.extraConfig;
      message = "auth vhost should require client certificates";
    }
    {
      condition = hasInfix "include /var/lib/pseudo-design/auth/deny-fingerprints.map;" authConfig.services.nginx.commonHttpConfig;
      message = "nginx should include the fingerprint denylist map";
    }
    {
      condition = authLocation.proxyPass == "http://127.0.0.1:8080";
      message = "auth vhost should proxy to the configured upstream";
    }
    {
      condition = lib.elem "pseudo-design-ca-create-intermediate-csr" authPackageNames;
      message = "auth server should install the online intermediate CSR command";
    }
    {
      condition = lib.elem "pseudo-design-ca-install-intermediate-cert" authPackageNames;
      message = "auth server should install the online intermediate certificate install command";
    }
    {
      condition = rootCertService.serviceConfig.Type == "oneshot";
      message = "auth server should install the configured root certificate with a one-shot service";
    }
    {
      condition = hasInfix "/var/lib/step-ca/certs/root_ca.crt" rootCertService.script;
      message = "root certificate install service should target step-ca root certificate path";
    }
    {
      condition = hasInfix "proxy_set_header X-Pseudo-Design-Client-Fingerprint $ssl_client_fingerprint;" authLocation.extraConfig;
      message = "auth vhost should pass client fingerprint to upstreams";
    }
    {
      condition = hasInfix "proxy_set_header X-Pseudo-Design-Client-Cert $ssl_client_escaped_cert;" authLocation.extraConfig;
      message = "auth vhost should pass escaped client certificate to upstreams";
    }
    {
      condition = lib.all (path: lib.elem path authBundleService.unitConfig.ConditionPathExists) [
        "/var/lib/step-ca/certs/root_ca.crt"
        "/var/lib/step-ca/certs/intermediate_ca.crt"
      ];
      message = "auth CA bundle should wait for root and intermediate certificates";
    }
    {
      condition = hasInfix "/var/lib/step-ca/certs/intermediate_ca.crt" authBundleService.script;
      message = "auth CA bundle should include the intermediate certificate for nginx client verification";
    }
    {
      condition = !lib.any (hasInfix "enrollmentProvisionerPublicKey") authConfig.warnings;
      message = "configured public JWK should suppress the enrollment provisioner warning";
    }
    {
      condition =
        runtimeAuthServer.enrollmentProvisionerPublicKeyFile == runtimeEnrollmentProvisionerPublicKeyFile;
      message = "auth server should accept a runtime enrollment public JWK file";
    }
    {
      condition = runtimeStepCaSettings.authority.provisioners == [ ];
      message = "runtime enrollment public JWK mode should not bake a provisioner into the Nix store ca.json";
    }
    {
      condition = lib.any (hasInfix "/run/pseudo-design-step-ca/ca.json") runtimeStepCaService.serviceConfig.ExecStart;
      message = "runtime enrollment public JWK mode should run step-ca with a rendered runtime config";
    }
    {
      condition = runtimeStepCaConfigService.serviceConfig.Type == "oneshot";
      message = "runtime step-ca config renderer should be a one-shot service";
    }
    {
      condition = hasInfix runtimeEnrollmentProvisionerPublicKeyFile runtimeStepCaConfigService.script;
      message = "runtime step-ca config renderer should read the configured public JWK file";
    }
    {
      condition = runtimeAuthVhost.enableACME == false;
      message = "auth vhost should allow ACME to be disabled for tests";
    }
    {
      condition = runtimeAuthVhost.sslCertificate == runtimeAuthTlsCertificateFile;
      message = "auth vhost should use the configured runtime TLS certificate when ACME is disabled";
    }
    {
      condition = runtimeAuthVhost.sslCertificateKey == runtimeAuthTlsKeyFile;
      message = "auth vhost should use the configured runtime TLS key when ACME is disabled";
    }
    {
      condition = lib.all (path: lib.elem path runtimeNginxService.unitConfig.ConditionPathExists) [
        runtimeAuthTlsCertificateFile
        runtimeAuthTlsKeyFile
      ];
      message = "nginx should wait for runtime TLS files when ACME is disabled";
    }
    {
      condition = !lib.any (hasInfix "enrollmentProvisionerPublicKey") runtimeAuthConfig.warnings;
      message = "runtime public JWK file should suppress the enrollment provisioner warning";
    }
  ];

  pseudo-design-offline-ca-module = mkCheck "pseudo-design-offline-ca-module" [
    {
      condition = offlineCa.enable;
      message = "offline CA module should be enabled";
    }
    {
      condition = offlineCa.stateDir == "/var/lib/pseudo-design/offline-ca";
      message = "offline CA state directory should use the fixed default";
    }
    {
      condition = offlineCa.exportDir == "/var/lib/pseudo-design/offline-ca/export";
      message = "offline CA export directory should default under the state directory";
    }
    {
      condition = lib.elem "d /var/lib/pseudo-design/offline-ca 0700 root root -" offlineCaConfig.systemd.tmpfiles.rules;
      message = "offline CA state directory should be root-only";
    }
    {
      condition = lib.elem "d /var/lib/pseudo-design/offline-ca/export 0700 root root -" offlineCaConfig.systemd.tmpfiles.rules;
      message = "offline CA export directory should be root-only";
    }
    {
      condition = lib.elem "pseudo-design-ca-bootstrap" offlineCaPackageNames;
      message = "offline CA bootstrap command should be installed";
    }
    {
      condition = lib.elem "pseudo-design-ca-export" offlineCaPackageNames;
      message = "offline CA export command should be installed";
    }
    {
      condition = lib.elem "pseudo-design-ca-sign-intermediate" offlineCaPackageNames;
      message = "offline CA intermediate signing command should be installed";
    }
    {
      condition = lib.elem "pseudo-design-ca-mint-token" offlineCaPackageNames;
      message = "offline CA token command should be installed";
    }
    {
      condition = lib.elem "step-kms-plugin" offlineCaPackageNames;
      message = "offline CA module should install step-kms-plugin for KMS-backed root operations";
    }
  ];

  pseudo-design-rootca-sd-image = mkCheck "pseudo-design-rootca-sd-image" [
    {
      condition = rootcaConfig.services.pseudoDesign.offlineCa.enable;
      message = "physical rootca should enable the offline CA service";
    }
    {
      condition = builtins.hasAttr "sdImage" rootcaBuild;
      message = "physical rootca should expose an SD-card image build";
    }
    {
      condition = builtins.hasAttr "rootca-sd-image" self.packages.aarch64-linux;
      message = "physical rootca SD image should have an aarch64 package alias";
    }
    {
      condition = rootcaConfig.fileSystems."/".device == "/dev/disk/by-label/NIXOS_SD";
      message = "physical rootca root filesystem should use the SD-card root label";
    }
    {
      condition = rootcaConfig.fileSystems."/boot/firmware".device == "/dev/disk/by-label/FIRMWARE";
      message = "physical rootca firmware filesystem should use the SD-card firmware label";
    }
    {
      condition =
        !lib.any (name: lib.elem name rootcaBuildAttrNames) [
          "disko"
          "diskoImages"
          "diskoScript"
          "formatScript"
          "mountScript"
        ];
      message = "physical rootca should not expose disko build products";
    }
  ];

  pseudo-design-ca-tools-split-intermediate-workflow =
    pkgs.runCommandLocal "pseudo-design-ca-tools-split-intermediate-workflow"
      {
        nativeBuildInputs = [
          caTools
          pkgs.coreutils
          pkgs.openssl
          pkgs.step-cli
        ];
      }
      ''
        set -euo pipefail

        export HOME="$TMPDIR/home"
        export PSEUDO_DESIGN_REPO_ROOT=/not-the-ca-state
        mkdir -p "$HOME"

        offline_dir="$TMPDIR/offline-ca"
        online_dir="$TMPDIR/online-ca"
        export_dir="$TMPDIR/export"
        signed_dir="$TMPDIR/signed"
        signed_cert="$signed_dir/intermediate_ca.crt"
        mkdir -p "$signed_dir"

        pseudo-design-ca-bootstrap "$offline_dir"
        test -s "$offline_dir/root_ca.crt"
        test -s "$offline_dir/root_ca.key"
        test -s "$offline_dir/root-password"
        test -s "$offline_dir/device-enrollment.pub.json"
        test -s "$offline_dir/device-enrollment.key.json"
        test -s "$offline_dir/provisioner-password"
        test -s "$offline_dir/root_ca.fingerprint"
        test ! -e "$offline_dir/intermediate_ca.key"
        test ! -e "$offline_dir/intermediate-password"

        pseudo-design-ca-export "$offline_dir" "$export_dir"
        test -s "$export_dir/public/root_ca.crt"
        test -s "$export_dir/public/root_ca.fingerprint"
        test -s "$export_dir/public/device-enrollment.pub.json"
        test -z "$(find "$export_dir" -name 'intermediate_ca.*' -o -name 'intermediate-password')"

        install -d -m 0750 "$online_dir/certs" "$online_dir/secrets"
        install -m 0644 "$offline_dir/root_ca.crt" "$online_dir/certs/root_ca.crt"

        pseudo-design-ca-create-intermediate-csr "$online_dir"
        test -s "$online_dir/certs/intermediate_ca.csr"
        test -s "$online_dir/secrets/intermediate_ca.key"
        test ! -e "$online_dir/certs/intermediate_ca.crt"

        pseudo-design-ca-sign-intermediate \
          "$online_dir/certs/intermediate_ca.csr" \
          "$signed_cert" \
          "$offline_dir"
        test -s "$signed_cert"

        pseudo-design-ca-install-intermediate-cert "$signed_cert" "$online_dir"
        test -s "$online_dir/certs/intermediate_ca.crt"
        openssl verify -CAfile "$online_dir/certs/root_ca.crt" "$online_dir/certs/intermediate_ca.crt"
        openssl x509 -in "$online_dir/certs/intermediate_ca.crt" -noout -pubkey > "$TMPDIR/cert.pub"
        openssl pkey -in "$online_dir/secrets/intermediate_ca.key" -pubout > "$TMPDIR/key.pub"
        cmp -s "$TMPDIR/cert.pub" "$TMPDIR/key.pub"

        touch "$out"
      '';

  pseudo-design-pki-e2e-vm = import ./pseudo-design-pki-e2e-vm.nix {
    inherit
      lib
      pkgs
      self
      system
      ;
  };
}
