{
  lib,
  pkgs,
  self,
  system,
}:

let
  softHsmModule = "${pkgs.softhsm}/lib/softhsm/libsofthsm2.so";
  softHsmConfig = "/var/lib/pseudo-design/mock-yubikey/softhsm2.conf";
  rootKms = "pkcs11:module-path=${softHsmModule};token=pseudo-design-root?pin-value=123456";
  rootKey = "pkcs11:id=1000;object=root-ca";
in
pkgs.testers.nixosTest {
  name = "pseudo-design-pki-e2e-vm";

  nodes = {
    offlineca =
      { pkgs, ... }:
      {
        imports = [ self.nixosModules.pseudo-design-offline-ca ];

        networking.hostName = "offlineca";

        services.pseudoDesign.offlineCa.enable = true;

        environment.systemPackages = [
          pkgs.softhsm
          pkgs.step-kms-plugin
        ];

        virtualisation.memorySize = 768;
      };

    intermediateca =
      { pkgs, ... }:
      {
        imports = [ self.nixosModules.pseudo-design-auth-server ];

        networking.hostName = "intermediateca";

        services.pseudoDesign.authServer = {
          enable = true;
          domain = "test";
          caHost = "intermediateca";
          authHost = "intermediateca";
          enrollmentProvisionerPublicKeyFile = "/var/lib/step-ca/certs/device-enrollment.pub.json";
          enableAcme = false;
          authTlsCertificateFile = "/var/lib/pseudo-design/auth/server.fullchain.crt";
          authTlsKeyFile = "/var/lib/pseudo-design/auth/server.key";
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

  testScript = # python
    ''
      import base64


      def read_b64(machine, path):
          return machine.succeed(f"base64 -w0 {path}").strip()


      def write_b64(machine, path, data, mode="0644", owner=None):
          machine.succeed(f"mkdir -p $(dirname {path})")
          machine.succeed(f"printf '%s' '{data}' | base64 -d > {path}")
          machine.succeed(f"chmod {mode} {path}")
          if owner is not None:
              machine.succeed(f"chown {owner} {path}")


      def transfer(src_machine, src_path, dst_machine, dst_path, mode="0644", owner=None):
          write_b64(dst_machine, dst_path, read_b64(src_machine, src_path), mode, owner)


      def write_text(machine, path, text, mode="0644", owner=None):
          data = base64.b64encode(text.encode("utf-8")).decode("ascii")
          write_b64(machine, path, data, mode, owner)


      start_all()
      offlineca.wait_for_unit("multi-user.target")
      intermediateca.wait_for_unit("multi-user.target")
      leafdevice.wait_for_unit("multi-user.target")

      offlineca.succeed("""
        set -euo pipefail
        install -d -m 0700 /var/lib/pseudo-design/mock-yubikey/tokens
        printf '%s\n' \
          'directories.tokendir = /var/lib/pseudo-design/mock-yubikey/tokens' \
          'objectstore.backend = file' \
          > ${softHsmConfig}
        export SOFTHSM2_CONF=${softHsmConfig}
        softhsm2-util --init-token --free --label pseudo-design-root --pin 123456 --so-pin 12345678
        step kms create --kty EC --crv P256 --kms '${rootKms}' '${rootKey}' >/dev/null
        PSEUDO_DESIGN_CA_DOMAIN=test \
        PSEUDO_DESIGN_CA_URL=https://intermediateca:8443 \
        PSEUDO_DESIGN_CA_ROOT_KMS='${rootKms}' \
        PSEUDO_DESIGN_CA_ROOT_KEY='${rootKey}' \
          pseudo-design-ca-bootstrap
      """)

      offlineca.succeed("test -s /var/lib/pseudo-design/offline-ca/root_ca.crt")
      offlineca.succeed("test -s /var/lib/pseudo-design/offline-ca/root_ca.fingerprint")
      offlineca.succeed("test -s /var/lib/pseudo-design/offline-ca/device-enrollment.pub.json")
      offlineca.succeed("test -s /var/lib/pseudo-design/offline-ca/device-enrollment.key.json")
      offlineca.succeed("test -s /var/lib/pseudo-design/offline-ca/provisioner-password")
      offlineca.succeed("test ! -e /var/lib/pseudo-design/offline-ca/root_ca.key")
      offlineca.succeed("test ! -e /var/lib/pseudo-design/offline-ca/root-password")
      offlineca.succeed("test -z \"$(find /var/lib/pseudo-design/offline-ca \\( -name intermediate_ca.key -o -name device.key \\) -print)\"")

      transfer(
          offlineca,
          "/var/lib/pseudo-design/offline-ca/root_ca.crt",
          intermediateca,
          "/var/lib/step-ca/certs/root_ca.crt",
          owner="step-ca:step-ca",
      )
      transfer(
          offlineca,
          "/var/lib/pseudo-design/offline-ca/device-enrollment.pub.json",
          intermediateca,
          "/var/lib/step-ca/certs/device-enrollment.pub.json",
          owner="step-ca:step-ca",
      )

      intermediateca.succeed("pseudo-design-ca-create-intermediate-csr")
      intermediateca.succeed("test -s /var/lib/step-ca/certs/intermediate_ca.csr")
      intermediateca.succeed("test -s /var/lib/step-ca/secrets/intermediate_ca.key")
      intermediateca.succeed("test ! -e /var/lib/step-ca/certs/intermediate_ca.crt")

      transfer(
          intermediateca,
          "/var/lib/step-ca/certs/intermediate_ca.csr",
          offlineca,
          "/tmp/intermediate_ca.csr",
      )
      offlineca.succeed("""
        set -euo pipefail
        export SOFTHSM2_CONF=${softHsmConfig}
        PSEUDO_DESIGN_CA_DOMAIN=test \
        PSEUDO_DESIGN_CA_URL=https://intermediateca:8443 \
        PSEUDO_DESIGN_CA_ROOT_KMS='${rootKms}' \
        PSEUDO_DESIGN_CA_ROOT_KEY='${rootKey}' \
          pseudo-design-ca-sign-intermediate /tmp/intermediate_ca.csr /tmp/intermediate_ca.crt
      """)
      transfer(
          offlineca,
          "/tmp/intermediate_ca.crt",
          intermediateca,
          "/tmp/intermediate_ca.crt",
      )
      intermediateca.succeed("pseudo-design-ca-install-intermediate-cert /tmp/intermediate_ca.crt")
      intermediateca.succeed("test -s /var/lib/step-ca/certs/intermediate_ca.crt")

      intermediateca.succeed("""
        set -euo pipefail
        install -d -m 0755 /var/lib/pseudo-design/auth
        step certificate create \
          intermediateca \
          /var/lib/pseudo-design/auth/server.crt \
          /var/lib/pseudo-design/auth/server.key \
          --profile leaf \
          --ca /var/lib/step-ca/certs/intermediate_ca.crt \
          --ca-key /var/lib/step-ca/secrets/intermediate_ca.key \
          --no-password \
          --insecure \
          --san intermediateca \
          --force
        cat /var/lib/pseudo-design/auth/server.crt \
          /var/lib/step-ca/certs/intermediate_ca.crt \
          > /var/lib/pseudo-design/auth/server.fullchain.crt
        chmod 0644 /var/lib/pseudo-design/auth/server.crt /var/lib/pseudo-design/auth/server.fullchain.crt
        chown nginx:nginx /var/lib/pseudo-design/auth/server.key
        chmod 0640 /var/lib/pseudo-design/auth/server.key
      """)

      intermediateca.succeed("systemctl start pseudo-design-step-ca-config.service")
      intermediateca.succeed("systemctl start step-ca.service")
      intermediateca.wait_for_open_port(8443)
      intermediateca.succeed("systemctl start pseudo-design-auth-ca-bundle.service")
      intermediateca.succeed("systemctl restart nginx.service")
      intermediateca.wait_for_unit("nginx.service")

      transfer(
          offlineca,
          "/var/lib/pseudo-design/offline-ca/root_ca.fingerprint",
          leafdevice,
          "/run/keys/pseudo-design-ca-fingerprint",
          mode="0444",
      )
      transfer(
          intermediateca,
          "/var/lib/step-ca/certs/intermediate_ca.crt",
          leafdevice,
          "/tmp/intermediate_ca.crt",
      )
      token = offlineca.succeed("""
        set -euo pipefail
        PSEUDO_DESIGN_CA_DOMAIN=test \
        PSEUDO_DESIGN_CA_URL=https://intermediateca:8443 \
          pseudo-design-ca-mint-token leafdevice
      """).strip()
      write_text(
          leafdevice,
          "/run/keys/pseudo-design-device-enrollment-token",
          token,
          mode="0400",
      )

      leafdevice.succeed("systemctl start pseudo-design-device-enroll.service")
      leafdevice.succeed("test -s /var/lib/pseudo-design/device-identity/device.key")
      leafdevice.succeed("test -s /var/lib/pseudo-design/device-identity/device.crt")
      leafdevice.succeed("test ! -e /run/keys/pseudo-design-device-enrollment-token")
      leafdevice.succeed(
          "openssl verify -CAfile /var/lib/pseudo-design/device-identity/root_ca.crt "
          "-untrusted /tmp/intermediate_ca.crt "
          "/var/lib/pseudo-design/device-identity/device.crt"
      )
      leafdevice.succeed("openssl x509 -in /var/lib/pseudo-design/device-identity/device.crt -noout -text | grep DNS:leafdevice.devices.test")
      leafdevice.succeed("openssl x509 -in /var/lib/pseudo-design/device-identity/device.crt -noout -text | grep URI:spiffe://test/device/leafdevice")

      leafdevice.succeed("""
        set -euo pipefail
        code="$(curl -sS -o /tmp/no-client-cert.out -w '%{http_code}' \
          --cacert /var/lib/pseudo-design/device-identity/root_ca.crt \
          https://intermediateca/ || true)"
        test "$code" != 200
      """)
      leafdevice.succeed("""
        set -euo pipefail
        curl -sS \
          --cacert /var/lib/pseudo-design/device-identity/root_ca.crt \
          --cert /var/lib/pseudo-design/device-identity/device.crt \
          --key /var/lib/pseudo-design/device-identity/device.key \
          https://intermediateca/ | grep authenticated
      """)
    '';
}
