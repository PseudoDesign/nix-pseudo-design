{
  lib,
  pdPki,
  pkgs,
  ...
}:

let
  rootInventoryRoot = pdPki + "/inventory/root-ca";
  rootInventoryEntries = builtins.attrNames (builtins.readDir rootInventoryRoot);
  rootInventoryId =
    if rootInventoryEntries == [ ] then
      throw "pd-pki input does not contain a root CA inventory entry"
    else
      builtins.head (lib.sort (left: right: left < right) rootInventoryEntries);
  rootCertificateFile = rootInventoryRoot + "/${rootInventoryId}/root-ca.cert.pem";
  enrollmentProvisionerPublicKeyFile =
    pdPki + "/inventory/device-enrollment/default/device-enrollment.pub.json";
  pdPkiIntermediateStateDir = "/var/lib/pd-pki/authorities/intermediate";
  pdPkiIntermediateKeyFile = "${pdPkiIntermediateStateDir}/intermediate-ca.key.pem";
in
{
  imports = [ pdPki.nixosModules.intermediate-signing-authority ];

  networking = {
    hostName = "mako";
    firewall.allowedTCPPorts = [
      80
      443
    ];
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "admin@pseudo.design";
  };

  services.pseudoDesign.authServer = {
    enable = true;
    inherit pdPkiIntermediateStateDir;
    rootCertificateSourceFile = rootCertificateFile;
  }
  // lib.optionalAttrs (builtins.pathExists enrollmentProvisionerPublicKeyFile) {
    enrollmentProvisionerPublicKey = builtins.fromJSON (
      builtins.readFile enrollmentProvisionerPublicKeyFile
    );
  };

  services.pd-pki.roles.intermediateSigningAuthority = {
    enable = true;
    stateDir = pdPkiIntermediateStateDir;
    provisioningUnits = [ "pseudo-design-step-ca-intermediate-key.service" ];
    request = {
      basename = "intermediate-ca";
      commonName = "Pseudo Design Intermediate CA";
      pathLen = 0;
      requestedDays = 3650;
      key.algorithm = "ec-p256";
    };
  };

  systemd.services.pseudo-design-step-ca-intermediate-key = {
    description = "Create the mako-local online intermediate CA key";
    before = [ "pd-pki-intermediate-signing-authority-init.service" ];
    after = [ "systemd-tmpfiles-setup.service" ];
    path = [
      pkgs.coreutils
      pkgs.openssl
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      UMask = "0077";
    };
    script = ''
      set -euo pipefail

      install -d -m 0700 ${pdPkiIntermediateStateDir}
      if [ ! -s ${pdPkiIntermediateKeyFile} ]; then
        openssl genpkey \
          -algorithm EC \
          -pkeyopt ec_paramgen_curve:prime256v1 \
          -pkeyopt ec_param_enc:named_curve \
          -out ${pdPkiIntermediateKeyFile}
      fi
      chmod 0600 ${pdPkiIntermediateKeyFile}
    '';
  };

  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedTlsSettings = true;

    virtualHosts."pseudo.design" = {
      root = ./site;
      serverAliases = [ "www.pseudo.design" ];
      enableACME = true;
      forceSSL = true;

      locations."/".tryFiles = "$uri $uri/ =404";

      extraConfig = ''
        add_header Strict-Transport-Security "max-age=31536000" always;
        add_header Content-Security-Policy "default-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'; style-src 'self'; img-src 'self'; object-src 'none'; script-src 'none'; upgrade-insecure-requests" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header X-Frame-Options "DENY" always;
      '';
    };
  };
}
