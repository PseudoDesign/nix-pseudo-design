# nix-pseudo-design

NixOS configurations for the `ace`, `mako`, and `rootca` Raspberry Pi 5 hosts,
plus a local `rootca-vm` for running the root CA workflow in a VM.

The `ace` and `mako` Pi systems share a generic Raspberry Pi 5 hardware
configuration that boots from NVMe and unlocks a LUKS encrypted root filesystem
with a key derived from the Raspberry Pi OTP private key. The physical `rootca`
host is built as a dedicated plain SD-card image for offline CA operations.

## Systems

```shell
nix eval --raw .#nixosConfigurations.ace.config.networking.hostName
nix eval --raw .#nixosConfigurations.mako.config.networking.hostName
nix eval --raw .#nixosConfigurations.rootca.config.networking.hostName
nix eval --raw .#nixosConfigurations.rootca-vm.config.networking.hostName
```

## Root CA VM

On an `x86_64-linux` host, run the offline root CA machine as a local NixOS VM:

```shell
nix run .#rootca-vm
```

The VM reuses the same `rootca` host module and stores its writable state in
`./rootca.qcow2` by default. The offline CA state therefore persists inside the
VM disk at `/var/lib/pseudo-design/offline-ca`.

The QEMU terminal logs in as `root` automatically. The VM also initializes a
VM-local SoftHSM PKCS#11 token at boot and configures the root CA tools to use
that emulated token for the root signing key. The physical `rootca` host does
not use these VM conveniences.

SSH is forwarded from the host to the VM on port `2222`:

```shell
ssh -p 2222 adam@localhost
```

From inside the VM, use the same root CA commands as the physical `rootca`
host:

```shell
sudo pseudo-design-ca-bootstrap
sudo pseudo-design-ca-export
sudo pseudo-design-ca-sign-intermediate /path/to/intermediate_ca.csr /path/to/intermediate_ca.crt
sudo pseudo-design-ca-mint-token ace
```

For production root CA custody, prefer the physical offline `rootca` host or an
HSM-backed setup. The VM is useful for local operations and rehearsal, but its
private CA material and emulated PKCS#11 token live wherever the `rootca.qcow2`
disk is stored.

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

### Install rootca on an SD card

Build the physical offline CA image:

```shell
nix build .#packages.aarch64-linux.rootca-sd-image
```

The canonical configuration build target is also available:

```shell
nix build .#nixosConfigurations.rootca.config.system.build.sdImage
```

Write the image to an SD card, replacing `/dev/sdX` with the whole card device:

```shell
zstdcat result/sd-image/pseudo-design-rootca-rpi5-sd-*.img.zst \
  | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

Boot the Raspberry Pi 5 from that SD card. The `rootca` image uses an
unencrypted ext4 root filesystem on the SD card; protect the card itself as the
offline CA custody boundary because `/var/lib/pseudo-design/offline-ca` stores
root CA private material after bootstrap.

## Device certificate auth

`mako` is configured as the `pseudo.design` certificate authority and mTLS auth
gateway:

- `ca.pseudo.design:8443` serves `step-ca` directly.
- `auth.pseudo.design` is an nginx vhost that requires a client certificate.
- Every Raspberry Pi host has a device identity service that can generate a
  local P-256 key, create a CSR, enroll with a one-time token, and renew the
  certificate automatically.

The offline `rootca` host stores the CA private material and enrollment signing
key under `/var/lib/pseudo-design/offline-ca`. Private material is intentionally
not stored in this repository or the Nix store. The non-secret CA workflow and
public artifacts live under `packages/pseudo-design-ca-tools/` and `ca/public/`.

See [docs/device-certificate-auth.md](docs/device-certificate-auth.md) for the
architecture, trust model, runtime files, and module-level change summary.

### Bootstrap the CA

Build and boot the offline CA SD-card image:

```shell
nix build --no-link .#nixosConfigurations.rootca.config.system.build.sdImage
```

On `rootca`, create the root CA and one-time-token provisioner in the fixed
root-only state directory:

```shell
sudo pseudo-design-ca-bootstrap
```

The non-secret CA settings are in
`packages/pseudo-design-ca-tools/config.sh` and are baked into the installed CA
commands. Override them in the script before deploying `rootca` if the domain,
names, or durations ever need to change.

Export public artifacts for removable-media transfer:

```shell
sudo pseudo-design-ca-export
```

This writes:

- `/var/lib/pseudo-design/offline-ca/export/public/` for commit-safe public
  artifacts.

Install the public artifacts into this repository and commit them:

```shell
EXPORT_PUBLIC=/path/to/removable-media/public
nix run .#ca-install-public-artifacts -- "$EXPORT_PUBLIC"

git add ca/public/root_ca.crt \
  ca/public/root_ca.fingerprint \
  ca/public/device-enrollment.pub.json
```

Once committed, `hosts/mako/default.nix` automatically configures the public
root certificate and enrollment JWK. `modules/profiles/base-rpi.nix`
automatically pins the root fingerprint for device enrollment.

Generate the online intermediate key and CSR on `mako`. The key is created under
`/var/lib/step-ca/secrets/intermediate_ca.key` and must never leave `mako`:

```shell
ssh root@mako.local
pseudo-design-ca-create-intermediate-csr
exit

scp root@mako.local:/var/lib/step-ca/certs/intermediate_ca.csr \
  /path/to/removable-media/intermediate_ca.csr
```

Sign that CSR on `rootca` using the offline root key:

```shell
sudo pseudo-design-ca-sign-intermediate \
  /path/to/removable-media/intermediate_ca.csr \
  /path/to/removable-media/intermediate_ca.crt
```

Copy only the signed intermediate certificate back to `mako`:

```shell
scp /path/to/removable-media/intermediate_ca.crt root@mako.local:/root/
ssh root@mako.local
pseudo-design-ca-install-intermediate-cert /root/intermediate_ca.crt
rm -f /root/intermediate_ca.crt
systemctl restart step-ca.service pseudo-design-auth-ca-bundle.service nginx.service
```

Keep `root_ca.key`, `root-password`, `device-enrollment.key.json`, and
`provisioner-password` offline on `rootca`. Keep `intermediate_ca.key` on
`mako`; it is online CA private material and is protected by file permissions and
the encrypted root filesystem.

### Enroll a device

Generate a short-lived, identity-bound token for the host you are enrolling:

```shell
HOST=ace
TOKEN="$(
  sudo pseudo-design-ca-mint-token "$HOST"
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

If the deployed host configuration does not yet include
`ca/public/root_ca.fingerprint`, also copy the exported `root_ca.fingerprint` to
`/run/keys/pseudo-design-ca-fingerprint` before starting enrollment.

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
