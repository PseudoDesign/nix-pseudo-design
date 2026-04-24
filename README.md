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

Boot the installer image, then start the install interactively. By default, the command installs from the flake bundled into the installer image, prints a summary, asks for confirmation, provisions the Raspberry Pi OTP private key if it is unset, derives `/run/secrets/luks.key` with `rpi-otp-derived-key`, and then hands off to `disko-install`, which will still prompt before wiping the target disk:

`sudo pd-nix-install`

To install a different NixOS configuration from the same local flake:

`sudo pd-nix-install ace`

If you want to troubleshoot key derivation separately after the OTP key has already been provisioned, you can run:

`sudo pd-luks-key-setup`

`ls -l /run/secrets/luks.key`

Any derivation errors are printed directly to the terminal.


## LUKS Filesystem

There are two instances where we need the LUKS filesystem key:

* Unlocking the disk in initrd
* Formatting the initial disk

This section covers how these operations are performed securely.

### Unlocking the Rootfs at Boot

```mermaid
sequenceDiagram
  participant initrd
  create participant rpi-otp-derived-key-luks.service
  initrd->>rpi-otp-derived-key-luks.service: Start Service
  create participant /run/secrets/luks.key@{ "type" : "database" }
  rpi-otp-derived-key-luks.service-->>/run/secrets/luks.key: upstream module writes key
  destroy rpi-otp-derived-key-luks.service
  rpi-otp-derived-key-luks.service->>initrd: Success
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

After booting from the EEPROM bootloader, execution is handed off to initrd. Using the upstream `nixos-raspberrypi` `rpiOtpDerivedKey` module, we add the following to the boot process:

* Run `rpi-otp-derived-key-luks.service` before `cryptsetup` unlocks the rootfs
  * This service derives the LUKS key into `/run/secrets/luks.key`
  * The derivation uses the Raspberry Pi OTP private key plus a repo-managed salt injected into initrd
* The `cryptsetup` service starts, unlocking the LUKS block containing the rootfs
  * This also unlocks any additional filesystem partitions loaded within the block (e.g. persistent user data)
* The system mounts into the rootfs and boots as normal.

## OpenVPN PKI

The repository now includes three role-focused NixOS modules for an offline-friendly OpenVPN PKI:

* `pd-openvpn-root-ca`: manages an air-gapped root CA host that creates a self-signed root certificate and signs the intermediate CA CSR.
* `pd-openvpn-intermediate-ca`: manages a second air-gapped host that creates its own CSR, imports the root-signed intermediate certificate, and signs OpenVPN server/client CSRs.
* `pd-openvpn-leaf`: manages an endpoint host that generates its own private key and CSR locally, then imports the signed certificate and CA chain after sneaker-net transfer.

The important design constraint is that private keys and issued certificates live under `/var/lib/pd-openvpn/...` at runtime. Nothing sensitive is generated into the Nix store.

### Example module usage

```nix
{
  imports = [
    inputs.self.nixosModules.pd-openvpn-root-ca
    inputs.self.nixosModules.pd-openvpn-intermediate-ca
    inputs.self.nixosModules.pd-openvpn-leaf
  ];
}
```

Root CA host:

```nix
{
  services.pdOpenvpnRootCA = {
    enable = true;
    subject = "/CN=Pseudo Design OpenVPN Root CA";
  };
}
```

Intermediate CA host:

```nix
{
  services.pdOpenvpnIntermediateCA = {
    enable = true;
    subject = "/CN=Pseudo Design OpenVPN Intermediate CA";
  };
}
```

OpenVPN server or client host:

```nix
{
  services.pdOpenvpnLeaf = {
    enable = true;
    subject = "/CN=openvpn-server";
    subjectAltNames = [ "DNS:openvpn-server.internal" ];
  };
}
```

### Operator workflow

1. On the root CA machine, run `pd-openvpn-root-ca-init`.
2. On the intermediate machine, run `pd-openvpn-intermediate-ca-init`.
3. Transfer `intermediate-ca.csr` to the root machine and sign it with `pd-openvpn-root-ca-sign-intermediate`.
4. Transfer the signed intermediate certificate and `root-ca.crt` back to the intermediate machine, then run `pd-openvpn-intermediate-ca-import-chain`.
5. On each OpenVPN server or client host, run `pd-openvpn-leaf-init` if the CSR has not already been created automatically at boot.
6. Transfer the leaf CSR to the intermediate machine and sign it with `pd-openvpn-intermediate-ca-sign-server` or `pd-openvpn-intermediate-ca-sign-client`.
7. Transfer the signed leaf certificate plus `ca-chain.crt` back to the endpoint and import them with `pd-openvpn-leaf-import-certificate`.
8. Point OpenVPN at the imported key, cert, and chain paths reported by `pd-openvpn-leaf-paths`.

The intermediate signer applies OpenVPN-friendly certificate profiles:

* Server certificates get `extendedKeyUsage = serverAuth` and `nsCertType = server`.
* Client certificates get `extendedKeyUsage = clientAuth` and `nsCertType = client`.
* Leaf CSRs can request SANs, and the intermediate signer copies those SAN extensions into the signed certificate.

This first pass does not yet manage revocation lists or OpenVPN service configuration directly.
