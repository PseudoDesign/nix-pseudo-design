# nix-pseudo-design

NixOS configurations for the `ace` and `mako` Raspberry Pi 5 hosts.

Both systems share a generic Raspberry Pi 5 hardware configuration that boots
from NVMe and unlocks a LUKS encrypted root filesystem with a key derived from
the Raspberry Pi OTP private key.

## Systems

```shell
nix eval --raw .#nixosConfigurations.ace.config.networking.hostName
nix eval --raw .#nixosConfigurations.mako.config.networking.hostName
```

## Installation

Build or use the Raspberry Pi 5 installer image from the same
`nixos-raspberrypi` branch used by this flake:

```shell
NIXOS_RPI_FLAKE=github:ams-tech/nixos-raspberrypi/topic/rpi-otp-private-key
nix build "$NIXOS_RPI_FLAKE#installerImages.rpi5"
```

Write the installer image to an SD card, replacing `/dev/sdX` with the whole
card device:

```shell
zstdcat result/sd-image/nixos-installer-rpi5-kernel.img.zst \
  | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

Boot the Raspberry Pi 5 from the installer SD card with the NVMe drive attached.
The target disk defaults to `/dev/nvme0n1`.

> Warning: installing either host destroys `/dev/nvme0n1`.

Check whether the board already has an OTP private key:

```shell
sudo rpi-otp-private-key -c
```

If it is not provisioned, generate and write one on the Raspberry Pi installer:

```shell
OTP_KEYDIR="$(mktemp -d /run/rpi-otp-private-key.XXXXXX)"
chmod 0700 "$OTP_KEYDIR"

nix run nixpkgs#openssl -- ecparam -name prime256v1 -genkey -noout -out "$OTP_KEYDIR/private_key.pem"
nix run nixpkgs#openssl -- ec -in "$OTP_KEYDIR/private_key.pem" -text -noout \
  | awk '/priv:/{flag=1; next} /pub:/{flag=0} flag' \
  | tr -d ' \n:' \
  | head -n1 > "$OTP_KEYDIR/d.hex"

sudo rpi-otp-private-key -w "$(cat "$OTP_KEYDIR/d.hex")"
sudo rpi-otp-private-key -c

rm -f "$OTP_KEYDIR/private_key.pem" "$OTP_KEYDIR/d.hex"
rmdir "$OTP_KEYDIR"
unset OTP_KEYDIR
```

Install one of the hosts with `nixos-anywhere`:

```shell
nix develop --command nixos-anywhere --flake .#ace root@nixos-installer.local
nix develop --command nixos-anywhere --flake .#mako root@nixos-installer.local
```

Or run `nixos-anywhere` directly from its upstream flake:

```shell
nix run github:nix-community/nixos-anywhere -- --flake .#ace root@nixos-installer.local
nix run github:nix-community/nixos-anywhere -- --flake .#mako root@nixos-installer.local
```

During install, the disko configuration stages a per-install random salt and
derived LUKS key under `/run`, formats the encrypted root filesystem, then
installs the salt into `/var/lib/rpi-otp-derived-key/salt/luks-key` on the
target system.

## Device certificate auth

`mako` is configured as the `pseudo.design` certificate authority and mTLS auth
gateway:

- `ca.pseudo.design:8443` serves `step-ca` directly.
- `auth.pseudo.design` is an nginx vhost that requires a client certificate.
- Every Raspberry Pi host has a device identity service that can generate a
  local P-256 key, create a CSR, enroll with a one-time token, and renew the
  certificate automatically.

The CA private material and enrollment signing key are intentionally not stored
in this repository.

See [docs/device-certificate-auth.md](docs/device-certificate-auth.md) for the
architecture, trust model, runtime files, and module-level change summary.

### Bootstrap the CA

Create the root CA, online intermediate CA, and one-time-token provisioner on an
offline or otherwise trusted machine:

```shell
mkdir -p pseudo-design-ca
cd pseudo-design-ca
umask 077

printf '%s\n' 'replace-with-root-password' > root-password
printf '%s\n' 'replace-with-intermediate-password' > intermediate-password
printf '%s\n' 'replace-with-provisioner-password' > provisioner-password

nix develop /path/to/nix-pseudo-design --command step certificate create \
  "Pseudo Design Root CA" root_ca.crt root_ca.key \
  --profile root-ca \
  --kty EC \
  --curve P-256 \
  --password-file root-password

nix develop /path/to/nix-pseudo-design --command step certificate create \
  "Pseudo Design Intermediate CA" intermediate_ca.crt intermediate_ca.key \
  --profile intermediate-ca \
  --ca root_ca.crt \
  --ca-key root_ca.key \
  --ca-password-file root-password \
  --password-file intermediate-password \
  --kty EC \
  --curve P-256

nix develop /path/to/nix-pseudo-design --command step crypto jwk create \
  device-enrollment.pub.json device-enrollment.key.json \
  --kty EC \
  --crv P-256 \
  --use sig \
  --password-file provisioner-password

nix develop /path/to/nix-pseudo-design --command step certificate fingerprint \
  root_ca.crt > root_ca.fingerprint
```

Copy only the online CA material to `mako`:

```shell
scp root_ca.crt intermediate_ca.crt intermediate_ca.key intermediate-password root@mako.local:/root/
ssh root@mako.local

install -d -o step-ca -g step-ca -m 0750 /var/lib/step-ca/certs /var/lib/step-ca/secrets
install -o step-ca -g step-ca -m 0644 /root/root_ca.crt /var/lib/step-ca/certs/root_ca.crt
install -o step-ca -g step-ca -m 0644 /root/intermediate_ca.crt /var/lib/step-ca/certs/intermediate_ca.crt
install -o step-ca -g step-ca -m 0600 /root/intermediate_ca.key /var/lib/step-ca/secrets/intermediate_ca.key

install -d -m 0700 /run/keys
install -m 0600 /root/intermediate-password /run/keys/pseudo-design-step-ca-intermediate-password
rm -f /root/root_ca.crt /root/intermediate_ca.crt /root/intermediate_ca.key /root/intermediate-password
systemctl restart step-ca.service pseudo-design-auth-ca-bundle.service nginx.service
```

Make the public JWK visible to Nix by copying `device-enrollment.pub.json` into
`hosts/mako/` and enabling the commented
`services.pseudoDesign.authServer.enrollmentProvisionerPublicKey` line in
`hosts/mako/default.nix`. The public JWK can be committed; keep
`device-enrollment.key.json` and `provisioner-password` offline.

### Enroll a device

Generate a short-lived, identity-bound token for the host you are enrolling:

```shell
HOST=ace
TOKEN="$(
  nix develop /path/to/nix-pseudo-design --command step ca token "device:$HOST" \
    --issuer device-enrollment \
    --key ./device-enrollment.key.json \
    --provisioner-password-file ./provisioner-password \
    --san "$HOST.devices.pseudo.design" \
    --san "spiffe://pseudo.design/device/$HOST" \
    --not-after 15m \
    --ca-url https://ca.pseudo.design:8443 \
    --root ./root_ca.crt
)"
```

Install the token and pinned root fingerprint on the Pi, then start enrollment:

```shell
ssh root@$HOST.local 'install -d -m 0700 /run/keys'
printf '%s' "$TOKEN" \
  | ssh root@$HOST.local 'install -m 0600 /dev/stdin /run/keys/pseudo-design-device-enrollment-token'
cat root_ca.fingerprint \
  | ssh root@$HOST.local 'install -m 0644 /dev/stdin /run/keys/pseudo-design-ca-fingerprint'

ssh root@$HOST.local systemctl start pseudo-design-device-enroll.service
ssh root@$HOST.local systemctl status pseudo-design-device-renew.timer
```

The Pi stores its client key and certificate under
`/var/lib/pseudo-design/device-identity/`. The enrollment token is removed after
successful enrollment. Renewal checks run hourly and renew when less than eight
hours remain on the 24-hour certificate.

### Use and revoke certificates

From an enrolled Pi:

```shell
curl \
  --cert /var/lib/pseudo-design/device-identity/device.crt \
  --key /var/lib/pseudo-design/device-identity/device.key \
  https://auth.pseudo.design/
```

Requests without a valid device certificate are rejected by nginx. To block a
certificate immediately, add its nginx `$ssl_client_fingerprint` value to
`/var/lib/pseudo-design/auth/deny-fingerprints.map` on `mako`:

```nginx
ABCD1234... 1;
```
