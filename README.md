# nix-pseudo-design

NixOS infrastructure for `pseudo.design`.

This repository is a small flake-based system configuration that currently manages a single host, `ace`, and layers in Home Manager for the `adam` user. The active host configuration targets a Raspberry Pi 5 and includes the machine-level NixOS setup, user account definition, and user-space configuration.

## Quickstart

**TODO: Link to document describing how to install nixos & set up qemu**

### Build the installer image

`nix build .#installerImages.rpi5 --refresh`

Note that this is significantly faster if you build it on an RPi5.  When running on Ubuntu, the system starts a QEMU instance and runs the build there.

This can be configured to use remote caches, but if you're bootstrapping infrastructure yourself on an x86 system, it'll take some time.

### Write the image to an SDCard

**TODO: Does this also work on USB?**

`zstdcat result/sd-image/nixos-installer-rpi5-kernel.img.zst | sudo dd of=/dev/mmcblk0 bs=1M status=progress`

### Install the system image to NVME

Boot the installer image, then prepare the LUKS key:

`sudo systemctl start pd-luks-key-setup.service`

`systemctl status pd-luks-key-setup.service`

`ls -l /run/secrets/luks.key`

Start the install interactively. `disko-install` will still prompt before wiping the target disk:

`sudo pd-nix-install`

Follow progress with:

`journalctl -u pd-luks-key-setup.service -f`


## LUKS Filesystem

There are two instances where we need the LUKS filesystem key:

* Unlocking the disk in initrd
* Formatting the initial disk

This section covers how these operations are performed securely.

### Unlocking the Rootfs at Boot

```mermaid
sequenceDiagram
  participant initrd
  create participant rpi-otp-luks-key.service
  initrd->>rpi-otp-luks-key.service: Start Service
  create participant /run/secrets/luks.key@{ "type" : "database" }
  rpi-otp-luks-key.service-->>/run/secrets/luks.key: /bin/rpi-otp-luks-key
  destroy rpi-otp-luks-key.service
  rpi-otp-luks-key.service->>initrd: Success
  create participant cryptsetup.service
  initrd->>cryptsetup.service: Start Service
  /run/secrets/luks.key-->>cryptsetup.service: Read File
  create participant rootfs@{ "type" : "database" }
  cryptsetup.service-->>rootfs: Unlock
  destroy cryptsetup.service
  cryptsetup.service->>initrd: Success
  destroy initrd
  initrd-)rootfs: Boot into rootfs
```

After booting from the EEPROM bootloader, execution is handed off to initrd.  Using systemd-initrd services, we add the following to the boot process:

* Run `rpi-otp-luks-key.service` before `cryptsetup` unlocks the rootfs
  * This service uses the `rpi-otp-luks-key` script to write the secret luks key to `/run/secrets/luks.key`
  * This script reads the raw secret value from OTP, and uses a one-way hash to generate the luks secret key.
* The `cryptsetup` service starts, unlocking the LUKS block containing the rootfs
  * This also unlocks any additional filesystem partitions loaded within the block (e.g. persistent user data)
* The system mounts into the rootfs and boots as normal.
