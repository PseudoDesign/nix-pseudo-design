# Device Certificate Auth

This document describes the device certificate authentication setup for the
`pseudo.design` Raspberry Pi fleet.

## Overview

This repo now owns only the online side of the PKI:

- `mako` runs `step-ca` on `ca.pseudo.design:8443`.
- `mako` serves `auth.pseudo.design` through nginx with client certificate
  verification enabled.
- Raspberry Pi hosts generate a local device key, create a CSR, enroll with a
  short-lived one-time token, and renew the resulting client certificate.
- Device certificates are valid for 24 hours and renew automatically before
  expiry.

Offline root CA images, root inventory, intermediate signing, and enrollment
token custody live in the pinned `pd-pki` flake input from
`PseudoDesign/nix-pd-pki`.

## Trust Model

The Raspberry Pi OTP-derived secret remains scoped to local disk unlock on
`ace` and `mako`. Device TLS identity uses a separate per-device P-256 private
key stored under `/var/lib/pseudo-design/device-identity/` on the encrypted root
filesystem.

The root CA private key, root signing policy, enrollment private JWK, and token
minting password stay offline in the `nix-pd-pki` appliance workflow. This repo
reads only public artifacts from the pinned flake input:

- public root inventory under `inventory/root-ca/`;
- public device enrollment JWK under `inventory/device-enrollment/`;
- `pd-pki-signing-tools` and NixOS modules used for the intermediate handoff.

`mako` creates and stores the online intermediate private key locally under
`/var/lib/pd-pki/authorities/intermediate/intermediate-ca.key.pem`. That key
never leaves `mako` and is protected by file permissions and the encrypted root
filesystem.

No CA passwords, enrollment tokens, root private keys, enrollment private JWKs,
or online intermediate private material are stored in the Nix store by this
configuration.

## Host Changes

`modules/services/pseudo-design-auth-server.nix` adds the auth-server side:

- configures `services.step-ca`;
- opens ports `80`, `443`, and `8443`;
- publishes `auth.pseudo.design` with Let's Encrypt server TLS;
- requires device client certificates on the auth vhost;
- forwards verified certificate identity to an upstream through
  `X-Pseudo-Design-Client-*` headers;
- maintains an nginx fingerprint denylist at
  `/var/lib/pseudo-design/auth/deny-fingerprints.map`;
- installs wrappers to export the pd-pki intermediate request bundle and import
  the signed intermediate bundle.

`hosts/mako/default.nix` imports
`pd-pki.nixosModules.intermediate-signing-authority`, installs the pinned public
root certificate for `step-ca`, reads the public enrollment JWK when present,
and configures the pd-pki intermediate request role.

`modules/services/pseudo-design-device-identity.nix` adds the device side:

- creates a root-only state directory;
- pins the CA root by fingerprint before bootstrap;
- creates a local P-256 key and CSR;
- signs the CSR with a one-time token;
- stores the resulting device cert and key on the Pi;
- runs a renewal timer that checks hourly and renews when less than eight hours
  remain.

`modules/profiles/base-rpi.nix` enables device identity on Raspberry Pi hosts
and pins the root fingerprint from the pd-pki root inventory.

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
- `/var/lib/pd-pki/authorities/intermediate/intermediate-ca.key.pem`
- `/var/lib/pd-pki/authorities/intermediate/intermediate-ca.csr.pem`
- `/var/lib/pd-pki/authorities/intermediate/signing-request.json`
- `/var/lib/pd-pki/authorities/intermediate/intermediate-ca.cert.pem`
- `/var/lib/pd-pki/authorities/intermediate/chain.pem`
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

Build offline root/provisioner/signer images from `nix-pd-pki`, not this repo.
After the public root inventory and public enrollment JWK are committed there,
update this repo's `pd-pki` lock and deploy `mako`.

The `mako` auth-server configuration installs:

- `pseudo-design-ca-export-intermediate-request`;
- `pseudo-design-ca-import-signed-intermediate`;
- `pd-pki-signing-tools`.

The intermediate handoff is bundle-based:

1. `mako` creates the online intermediate private key and pd-pki signing request.
2. `pseudo-design-ca-export-intermediate-request OUT_DIR` exports the request
   bundle for removable-media transfer.
3. The offline pd-pki appliance signs the request with
   `pd-pki-signing-tools sign-request`.
4. `pseudo-design-ca-import-signed-intermediate SIGNED_DIR` imports the signed
   bundle on `mako`.
5. Restart `step-ca.service`, `pseudo-design-auth-ca-bundle.service`, and
   `nginx.service`.

Enrollment is intentionally token-based and host-bound. The offline pd-pki
appliance mints tokens with:

```shell
pd-pki-signing-tools mint-device-enrollment-token \
  --state-dir /var/lib/pd-pki/device-enrollment \
  --root-cert /var/lib/pd-pki/root/root-ca.cert.pem \
  --host ace
```

The token subject and SANs are bound to the requested host and default to a
short lifetime.

## Verification

The flake checks cover:

- generated device enrollment and renewal units;
- auth-server `step-ca` and nginx configuration;
- removal of local offline root CA images, apps, modules, and packages;
- `mako` integration with the pinned pd-pki intermediate role;
- a VM PKI handoff test that uses pd-pki signing tools for request export,
  offline signing, signed import, and enrollment token minting.

Run:

```shell
nix flake check
```
