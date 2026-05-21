# nix-pseudo-design

NixOS configurations for the online `ace` and `mako` Raspberry Pi 5 hosts.
Offline root PKI images, root inventory, intermediate signing, and enrollment
token custody live in the separate
[`PseudoDesign/nix-pd-pki`](https://github.com/PseudoDesign/nix-pd-pki)
flake, which this repo pins as the `pd-pki` input.

The `ace` and `mako` Pi systems share a Raspberry Pi 5 hardware configuration
that boots from NVMe and unlocks a LUKS encrypted root filesystem with a key
derived from the Raspberry Pi OTP private key. `mako` runs the online
Smallstep intermediate CA, the device enrollment endpoint, and the nginx mTLS
auth gateway.

## Systems

```shell
nix eval --raw .#nixosConfigurations.ace.config.networking.hostName
nix eval --raw .#nixosConfigurations.mako.config.networking.hostName
```

The development shell includes the `pd-pki` operator and signing tools from the
pinned flake:

```shell
nix develop
pd-pki-signing-tools --help
pd-pki-operator --help
```

## Installation

### Install ace or mako on NVMe

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

> Warning: installing either `ace` or `mako` destroys `/dev/nvme0n1`.

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

Install `ace` or `mako` with `nixos-anywhere`:

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

## Device Certificate Auth

`mako` is configured as the `pseudo.design` certificate authority and mTLS auth
gateway:

- `ca.pseudo.design:8443` serves `step-ca` directly.
- `auth.pseudo.design` is an nginx vhost that requires a client certificate.
- Every Raspberry Pi host has a device identity service that can generate a
  local P-256 key, create a CSR, enroll with a one-time token, and renew the
  certificate automatically.

Offline CA operations are intentionally outside this repo. Build and operate
the root CA images from `nix-pd-pki`:

```shell
nix build github:PseudoDesign/nix-pd-pki#packages.aarch64-linux.rpi5-root-ca-sd-image
```

Commit the public root inventory and public device enrollment JWK in
`nix-pd-pki`, then update this repo's `pd-pki` lock to that commit:

```shell
nix flake lock --update-input pd-pki
```

Deploy `mako`. It creates the online intermediate key and request under
`/var/lib/pd-pki/authorities/intermediate`; the private key stays on `mako`.

Export the request bundle from `mako`:

```shell
ssh root@mako.local
pseudo-design-ca-export-intermediate-request /path/to/removable-media/request
exit
```

Sign that request on the offline `nix-pd-pki` appliance with
`pd-pki-signing-tools sign-request`, then import the signed bundle back on
`mako`:

```shell
scp -r /path/to/removable-media/signed root@mako.local:/root/signed-intermediate
ssh root@mako.local
pseudo-design-ca-import-signed-intermediate /root/signed-intermediate
rm -rf /root/signed-intermediate
systemctl restart step-ca.service pseudo-design-auth-ca-bundle.service nginx.service
```

Keep root keys, enrollment private JWKs, provisioner passwords, and minted
tokens offline in the `nix-pd-pki` appliance workflow. Keep the intermediate CA
private key on `mako`; it is online CA private material protected by file
permissions and the encrypted root filesystem.

### Enroll a Device

Mint a short-lived, identity-bound token on the offline `nix-pd-pki` appliance:

```shell
HOST=ace
TOKEN="$(
  sudo pd-pki-signing-tools mint-device-enrollment-token \
    --state-dir /var/lib/pd-pki/device-enrollment \
    --root-cert /var/lib/pd-pki/root/root-ca.cert.pem \
    --host "$HOST"
)"
```

Install the token on the Pi, then start enrollment:

```shell
ssh root@$HOST.local 'install -d -m 0700 /run/keys'
printf '%s' "$TOKEN" \
  | ssh root@$HOST.local 'install -m 0600 /dev/stdin /run/keys/pseudo-design-device-enrollment-token'

ssh root@$HOST.local systemctl start pseudo-design-device-enroll.service
ssh root@$HOST.local systemctl status pseudo-design-device-renew.timer
```

The Pi stores its client key and certificate under
`/var/lib/pseudo-design/device-identity/`. The enrollment token is removed after
successful enrollment. Renewal checks run hourly and renew when less than eight
hours remain on the 24-hour certificate.

### Use and Revoke Certificates

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

See [docs/device-certificate-auth.md](docs/device-certificate-auth.md) for the
architecture, trust model, runtime files, and module-level change summary.
