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


def read_dir_b64(machine, path):
    return machine.succeed(f"tar -C {path} -cf - . | base64 -w0").strip()


def write_dir_b64(machine, path, data):
    machine.succeed(f"rm -rf {path}")
    machine.succeed(f"mkdir -p {path}")
    machine.succeed(f"printf '%s' '{data}' | base64 -d | tar -C {path} -xf -")


def transfer_dir(src_machine, src_path, dst_machine, dst_path):
    write_dir_b64(dst_machine, dst_path, read_dir_b64(src_machine, src_path))


def write_text(machine, path, text, mode="0644", owner=None):
    data = base64.b64encode(text.encode("utf-8")).decode("ascii")
    write_b64(machine, path, data, mode, owner)


start_all()
offlineca.wait_for_unit("multi-user.target")
intermediateca.wait_for_unit("multi-user.target")
leafdevice.wait_for_unit("multi-user.target")

offlineca.succeed("""
set -euo pipefail

install -d -m 0700 /var/lib/pd-pki/root /var/lib/pd-pki/signer-state/root
openssl genpkey \
  -algorithm EC \
  -pkeyopt ec_paramgen_curve:prime256v1 \
  -pkeyopt ec_param_enc:named_curve \
  -out /var/lib/pd-pki/root/root-ca.key.pem
openssl req \
  -x509 \
  -new \
  -sha256 \
  -days 3650 \
  -key /var/lib/pd-pki/root/root-ca.key.pem \
  -subj '/CN=Pseudo Design Test Root CA' \
  -addext 'basicConstraints=critical,CA:TRUE,pathlen:1' \
  -addext 'keyUsage=critical,keyCertSign,cRLSign' \
  -out /var/lib/pd-pki/root/root-ca.cert.pem
openssl x509 -in /var/lib/pd-pki/root/root-ca.cert.pem -outform DER \
  | sha256sum \
  | cut -d ' ' -f1 \
  > /var/lib/pd-pki/root/root-ca.fingerprint

pd-pki-signing-tools init-device-enrollment-provisioner \
  --state-dir /var/lib/pd-pki/device-enrollment
pd-pki-signing-tools export-device-enrollment-public \
  --state-dir /var/lib/pd-pki/device-enrollment \
  --out-dir /var/lib/pd-pki/device-enrollment-public \
  --domain test \
  --ca-url https://intermediateca:8443
""")
write_text(
    offlineca,
    "/var/lib/pd-pki/root/root-signer-policy.json",
    """
{
  "schemaVersion": 1,
  "roles": {
    "intermediate-signing-authority": {
      "defaultDays": 3650,
      "maxDays": 3650,
      "allowedKeyAlgorithms": ["EC"],
      "commonNamePatterns": ["^Pseudo Design Intermediate CA$"],
      "allowedPathLens": [0]
    }
  }
}
""".lstrip(),
)

transfer(
    offlineca,
    "/var/lib/pd-pki/root/root-ca.cert.pem",
    intermediateca,
    "/var/lib/step-ca/certs/root_ca.crt",
    owner="step-ca:step-ca",
)
transfer(
    offlineca,
    "/var/lib/pd-pki/device-enrollment-public/device-enrollment.pub.json",
    intermediateca,
    "/var/lib/step-ca/certs/device-enrollment.pub.json",
    owner="step-ca:step-ca",
)

intermediateca.succeed("systemctl start pd-pki-intermediate-signing-authority-init.service")
intermediateca.succeed("test -s /var/lib/pd-pki/authorities/intermediate/intermediate-ca.key.pem")
intermediateca.succeed("test -s /var/lib/pd-pki/authorities/intermediate/intermediate-ca.csr.pem")
intermediateca.succeed("test -s /var/lib/pd-pki/authorities/intermediate/signing-request.json")
intermediateca.succeed("test ! -e /var/lib/pd-pki/authorities/intermediate/intermediate-ca.cert.pem")
intermediateca.succeed("pseudo-design-ca-export-intermediate-request /tmp/intermediate-request")
intermediateca.succeed("test -s /tmp/intermediate-request/request.json")
intermediateca.succeed("test -s /tmp/intermediate-request/intermediate-ca.csr.pem")

transfer_dir(intermediateca, "/tmp/intermediate-request", offlineca, "/tmp/intermediate-request")
offlineca.succeed("""
set -euo pipefail

pd-pki-signing-tools sign-request \
  --request-dir /tmp/intermediate-request \
  --out-dir /tmp/intermediate-signed \
  --issuer-key /var/lib/pd-pki/root/root-ca.key.pem \
  --issuer-cert /var/lib/pd-pki/root/root-ca.cert.pem \
  --signer-state-dir /var/lib/pd-pki/signer-state/root \
  --policy-file /var/lib/pd-pki/root/root-signer-policy.json \
  --approved-by nixos-test
""")
offlineca.succeed("test -s /tmp/intermediate-signed/intermediate-ca.cert.pem")
offlineca.succeed("test -s /tmp/intermediate-signed/chain.pem")

transfer_dir(offlineca, "/tmp/intermediate-signed", intermediateca, "/tmp/intermediate-signed")
intermediateca.succeed("pseudo-design-ca-import-signed-intermediate /tmp/intermediate-signed")
intermediateca.succeed("test -s /var/lib/pd-pki/authorities/intermediate/intermediate-ca.cert.pem")
intermediateca.succeed("test -s /var/lib/pd-pki/authorities/intermediate/chain.pem")

intermediateca.succeed("""
set -euo pipefail
install -d -m 0755 /var/lib/pseudo-design/auth
step certificate create \
  intermediateca \
  /var/lib/pseudo-design/auth/server.crt \
  /var/lib/pseudo-design/auth/server.key \
  --profile leaf \
  --ca /var/lib/pd-pki/authorities/intermediate/intermediate-ca.cert.pem \
  --ca-key /var/lib/pd-pki/authorities/intermediate/intermediate-ca.key.pem \
  --no-password \
  --insecure \
  --san intermediateca \
  --force
cat /var/lib/pseudo-design/auth/server.crt \
  /var/lib/pd-pki/authorities/intermediate/intermediate-ca.cert.pem \
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
    "/var/lib/pd-pki/root/root-ca.fingerprint",
    leafdevice,
    "/run/keys/pseudo-design-ca-fingerprint",
    mode="0444",
)
transfer(
    intermediateca,
    "/var/lib/pd-pki/authorities/intermediate/intermediate-ca.cert.pem",
    leafdevice,
    "/tmp/intermediate_ca.crt",
)
token = offlineca.succeed("""
set -euo pipefail
pd-pki-signing-tools mint-device-enrollment-token \
  --state-dir /var/lib/pd-pki/device-enrollment \
  --root-cert /var/lib/pd-pki/root/root-ca.cert.pem \
  --host leafdevice \
  --domain test \
  --ca-url https://intermediateca:8443
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
