{
  lib,
  pd-pki,
  pkgs,
  self,
  system,
}:

let
  pdPkiSigningTools = pd-pki.packages.${system}.pd-pki-signing-tools;
in
pkgs.testers.nixosTest {
  name = "pseudo-design-pki-e2e-vm";

  nodes = {
    offlineca =
      { pkgs, ... }:
      {
        networking.hostName = "offlineca";

        environment.systemPackages = [
          pdPkiSigningTools
          pkgs.openssl
        ];

        virtualisation.memorySize = 768;
      };

    intermediateca =
      { pkgs, ... }:
      let
        pdPkiIntermediateStateDir = "/var/lib/pd-pki/authorities/intermediate";
        pdPkiIntermediateKeyFile = "${pdPkiIntermediateStateDir}/intermediate-ca.key.pem";
      in
      {
        _module.args.pdPki = pd-pki;

        imports = [
          self.nixosModules.pseudo-design-auth-server
          pd-pki.nixosModules.intermediate-signing-authority
        ];

        networking.hostName = "intermediateca";

        services.pseudoDesign.authServer = {
          enable = true;
          domain = "test";
          caHost = "intermediateca";
          authHost = "intermediateca";
          pdPkiIntermediateStateDir = pdPkiIntermediateStateDir;
          enrollmentProvisionerPublicKeyFile = "/var/lib/step-ca/certs/device-enrollment.pub.json";
          enableAcme = false;
          authTlsCertificateFile = "/var/lib/pseudo-design/auth/server.fullchain.crt";
          authTlsKeyFile = "/var/lib/pseudo-design/auth/server.key";
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
          description = "Create the test online intermediate CA key";
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

        environment.systemPackages = [
          pkgs.curl
          pkgs.openssl
        ];

        virtualisation.memorySize = 1024;
      };

    leafdevice =
      { pkgs, ... }:
      {
        imports = [ self.nixosModules.pseudo-design-device-identity ];

        networking.hostName = "leafdevice";

        services.pseudoDesign.deviceIdentity = {
          enable = true;
          domain = "test";
          caUrl = "https://intermediateca:8443";
        };

        environment.systemPackages = [
          pkgs.curl
          pkgs.openssl
        ];

        virtualisation.memorySize = 768;
      };
  };

  testScript = builtins.readFile ./pseudo-design-pki-e2e-vm.py;
}
