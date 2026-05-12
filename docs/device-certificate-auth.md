# Device Certificate Auth

This document describes the device certificate authentication changes for the
`pseudo.design` Raspberry Pi fleet.

## Overview

The repo now defines a small private PKI and mTLS auth gateway around
Smallstep `step-ca`:

- `mako` runs `step-ca` on `ca.pseudo.design:8443`.
- `mako` serves `auth.pseudo.design` through nginx with client certificate
  verification enabled.
- Raspberry Pi hosts generate a local device key, create a CSR, enroll with a
  short-lived one-time token, and renew the resulting client certificate.
- Device certificates are valid for 24 hours and renew automatically before
  expiry.

The implementation avoids a custom CA protocol. It relies on `step-ca` for
certificate issuance and renewal, nginx for mTLS enforcement, and NixOS
systemd units for device enrollment and recurring renewal.

## Trust Model

The Raspberry Pi OTP-derived secret remains scoped to local disk unlock. Device
TLS identity uses a separate per-device P-256 private key stored under
`/var/lib/pseudo-design/device-identity/` on the encrypted root filesystem.

The root CA is expected to stay offline on the `rootca` host under
`/var/lib/pseudo-design/offline-ca`. `mako` only needs the public root
certificate, the online intermediate certificate, the encrypted intermediate
private key, and the intermediate key password supplied at runtime.

The enrollment provisioner has two halves:

- `device-enrollment.pub.json` is public and can be committed after generation.
- `device-enrollment.key.json` and its password stay offline and are used only
  to mint short-lived enrollment tokens.

The public root certificate, root fingerprint, and public enrollment JWK can be
committed. No CA passwords, enrollment tokens, private keys, or online
intermediate private material are stored in the Nix store by this configuration.

## Host Changes

`modules/services/pseudo-design-auth-server.nix` adds the auth-server side:

- configures `services.step-ca`;
- opens ports `80`, `443`, and `8443`;
- publishes `auth.pseudo.design` with Let's Encrypt server TLS;
- requires device client certificates on the auth vhost;
- forwards verified certificate identity to an upstream through
  `X-Pseudo-Design-Client-*` headers;
- maintains an nginx fingerprint denylist at
  `/var/lib/pseudo-design/auth/deny-fingerprints.map`.

`modules/services/pseudo-design-device-identity.nix` adds the device side:

- creates a root-only state directory;
- pins the CA root by fingerprint before bootstrap;
- creates a local P-256 key and CSR;
- signs the CSR with a one-time token;
- stores the resulting device cert and key on the Pi;
- runs a renewal timer that checks hourly and renews when less than eight hours
  remain.

`modules/services/pseudo-design-offline-ca.nix` adds the offline root CA side:

- installs `step-cli`, `openssl`, and fixed-path CA operation commands;
- creates `/var/lib/pseudo-design/offline-ca` as root-only state;
- exports public artifacts and `mako` staging material for removable-media
  transfer.

`modules/profiles/base-rpi.nix` enables device identity for every Raspberry Pi
host and pins `ca/public/root_ca.fingerprint` when that public artifact is
present. `hosts/mako/default.nix` enables the auth server on `mako` and imports
`hosts/mako/device-enrollment.pub.json` when that public artifact is present.

## Certificate Shape

Device certificates use:

- subject common name: `device:<hostname>`;
- DNS SAN: `<hostname>.devices.pseudo.design`;
- URI SAN: `spiffe://pseudo.design/device/<hostname>`;
- key usage: `digitalSignature`;
- extended key usage: `clientAuth`;
- lifetime: `24h`.

The URI SAN is the stable identity to prefer for authorization. The subject is
kept mainly for logs and operator readability.

## Runtime Files

On `mako`:

- `/var/lib/step-ca/certs/root_ca.crt`
- `/var/lib/step-ca/certs/intermediate_ca.crt`
- `/var/lib/step-ca/secrets/intermediate_ca.key`
- `/run/keys/pseudo-design-step-ca-intermediate-password`
- `/var/lib/pseudo-design/auth/device-root-ca.crt`
- `/var/lib/pseudo-design/auth/deny-fingerprints.map`

On each Pi:

- `/run/keys/pseudo-design-ca-fingerprint` if the root fingerprint has not been
  deployed through Nix yet
- `/run/keys/pseudo-design-device-enrollment-token`
- `/var/lib/pseudo-design/device-identity/root_ca.crt`
- `/var/lib/pseudo-design/device-identity/device.key`
- `/var/lib/pseudo-design/device-identity/device.crt`

The enrollment token is removed after successful enrollment.

## Operations

The README contains the runbook for CA bootstrap, device enrollment, test
requests, and emergency certificate blocking.

The offline CA tooling is packaged under `packages/pseudo-design-ca-tools/`:

- `config.sh` stores non-secret CA names, domain, durations, and provisioner
  settings.
- `bootstrap-offline-ca.sh` creates or reuses the offline CA working directory.
- `export-artifacts.sh` prepares public and `mako` staging directories for
  removable-media transfer.
- `install-public-artifacts.sh` copies commit-safe public artifacts into the
  repo.
- `mint-device-token.sh` creates short-lived, identity-bound enrollment tokens.

The `rootca` NixOS configuration installs fixed-path wrappers around those
scripts: `pseudo-design-ca-bootstrap`, `pseudo-design-ca-export`, and
`pseudo-design-ca-mint-token`.

The remaining required setup before enrolling real devices is to deploy
`rootca`, run the bootstrap and export commands there, commit the public
artifacts, deploy the updated NixOS configuration, and stage the online CA
material onto `mako`.

After that, enrollment is intentionally token-based and host-bound:
`mint-device-token.sh` includes the exact subject and SANs for the target
device and defaults tokens to a 15-minute lifetime.

## Verification

The implementation was checked with:

```shell
nix flake check
nix build --no-link .#nixosConfigurations.ace.config.system.build.toplevel
nix build --no-link .#nixosConfigurations.mako.config.system.build.toplevel
nix build --no-link .#nixosConfigurations.rootca.config.system.build.toplevel
git diff --cached --check
```

`nix flake check` includes targeted module checks for the generated device
enrollment/renewal units and the auth-server `step-ca`/nginx configuration.

The current `mako` build warns until `hosts/mako/device-enrollment.pub.json` is
committed. That warning is expected before public CA artifacts are installed.
