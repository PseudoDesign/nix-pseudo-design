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
NIXOS_RPI_FLAKE=github:ams-tech/nixos-raspberrypi/codex/rpi-otp-upstream-improvements
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

## Encryption scheme upgrades

Existing `ace` and `mako` volumes were enrolled with the original HKDF-based
derivation. The shared hardware module therefore defaults to
`legacy-hkdf-v1`, which reproduces their existing LUKS key. Preserve and back
up each machine's `/var/lib/rpi-otp-derived-key/salt/luks-key`; changing or
losing it changes the derived key.

The disko provisioning hook reads the same final module option, so a fresh
format and the installed initrd cannot accidentally use different schemes.
For a destructive fresh install, override the host after confirming that the
installer firmware supports the firmware HMAC API:

```nix
services.rpiOtpDerivedKey.secrets.luks-key.scheme = "firmware-hmac-v1";
```

Do not apply that override directly to an existing volume. First boot the new
configuration with `legacy-hkdf-v1`, add and test a separate recovery
credential, derive the firmware-HMAC key from the existing salt, and enroll it
in another LUKS keyslot. Switch the host to `firmware-hmac-v1` only after that
new keyslot has been tested; remove the legacy keyslot only after a successful
cold boot and recovery test.
