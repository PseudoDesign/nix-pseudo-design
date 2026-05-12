{
  nixpkgs,
  self,
  system,
}:

let
  lib = nixpkgs.lib;
  pkgs = import nixpkgs { inherit system; };

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
      checked =
        lib.foldl' (
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
      };
    }
  ];

  authServer = authConfig.services.pseudoDesign.authServer;
  stepCa = authConfig.services.step-ca;
  stepCaSettings = stepCa.settings;
  provisioner = builtins.head stepCaSettings.authority.provisioners;
  authVhost = authConfig.services.nginx.virtualHosts.${authServer.authHost};
  authLocation = authVhost.locations."/";

  offlineCaConfig = mkConfig [
    self.nixosModules.pseudo-design-offline-ca
    {
      services.pseudoDesign.offlineCa.enable = true;
    }
  ];

  offlineCa = offlineCaConfig.services.pseudoDesign.offlineCa;
  offlineCaPackageNames = map lib.getName offlineCaConfig.environment.systemPackages;
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
      condition = stepCaSettings.db == {
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
      condition = hasInfix "proxy_set_header X-Pseudo-Design-Client-Fingerprint $ssl_client_fingerprint;" authLocation.extraConfig;
      message = "auth vhost should pass client fingerprint to upstreams";
    }
    {
      condition = hasInfix "proxy_set_header X-Pseudo-Design-Client-Cert $ssl_client_escaped_cert;" authLocation.extraConfig;
      message = "auth vhost should pass escaped client certificate to upstreams";
    }
    {
      condition = !lib.any (hasInfix "enrollmentProvisionerPublicKey") authConfig.warnings;
      message = "configured public JWK should suppress the enrollment provisioner warning";
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
      condition = lib.elem "pseudo-design-ca-mint-token" offlineCaPackageNames;
      message = "offline CA token command should be installed";
    }
  ];
}
