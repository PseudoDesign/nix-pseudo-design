# `pd-ca` Manual Operations

This guide is for operators who run `pd-ca` directly by hand.

`pd-ca` exposes two layers of commands:

* Workspace-oriented commands for the normal OpenVPN workflow.
* Lower-level CA primitives for recovery work, custom layouts, or debugging.

Most users should stay on the workspace-oriented commands. They maintain the
expected workspace layout, published bundle files, issuance history, and CRL
updates for you.

The workspace-oriented commands use a verb plus profile form such as
`issue openvpn-server ...` or `revoke openvpn-client ...`.

## Before You Start

Keep the CA workspace outside Git and treat it like other secret-bearing
material.

```bash
export PD_PKI="$HOME/.local/share/pseudo-design/pki"
install -d -m 0700 "$PD_PKI"
```

The standard workspace layout is:

```text
$PD_PKI/
  authorities/
    root/
    intermediate/
  issued/
    openvpn/
      servers/
      clients/
  history/
    openvpn/
      servers/
      clients/
  bundles/
```

`bundles/` is public-consumer material only. Private keys live under
`authorities/`, `issued/`, or `history/`.

## Normal OpenVPN Workflow

### 1. Create The Workspace Skeleton

This step is optional because the higher-level commands create the same
directories automatically, but it is useful when you want to inspect the layout
before adding CA material.

```bash
nix run .#pd-ca -- init-workspace "$PD_PKI"
```

No private keys are created in this step.

### 2. Initialize The Root CA

Run this once for a new workspace:

```bash
nix run .#pd-ca -- init-root-ca "$PD_PKI" "Pseudo Design Root CA"
```

This creates `authorities/root/` plus the initial public bundle files. The root
private signing key is created at `authorities/root/ca.key`.

### 3. Initialize The OpenVPN Intermediate

Run this once after the root exists:

```bash
nix run .#pd-ca -- init-intermediate-ca \
  "$PD_PKI" \
  "Pseudo Design OpenVPN Intermediate CA"
```

After that, `bundles/openvpn-ca.crt` contains the OpenVPN trust chain and
`bundles/openvpn-ca.crl.pem` contains the CRL peers should consult. The
intermediate private signing key is created at
`authorities/intermediate/ca.key`.

### 4. Issue OpenVPN Identities

Issue a server identity:

```bash
nix run .#pd-ca -- issue openvpn-server "$PD_PKI" ace "vpn.pseudo.design"
```

Issue a client identity:

```bash
nix run .#pd-ca -- issue openvpn-client "$PD_PKI" adam-laptop "adam-laptop"
```

The resulting directories contain the leaf certificate, key, CA chain, full
chain, and metadata files:

```text
$PD_PKI/issued/openvpn/servers/ace/
$PD_PKI/issued/openvpn/clients/adam-laptop/
```

The private keys land at:

* `$PD_PKI/issued/openvpn/servers/ace/ace.key`
* `$PD_PKI/issued/openvpn/clients/adam-laptop/adam-laptop.key`

### 5. Renew Existing Identities

Renewal issues a fresh certificate for the same logical identity and archives
the previous keypair under `history/`. Renewal does not revoke the archived
certificate.

```bash
nix run .#pd-ca -- renew openvpn-server "$PD_PKI" ace
nix run .#pd-ca -- renew openvpn-client "$PD_PKI" adam-laptop
```

Use renewal when you want a new certificate but do not need to invalidate the
previous one immediately. The replacement private key ends up back in the
identity's normal `issued/` directory, but it is created first in a hidden
temporary workspace directory such as `$PD_PKI/.renew-server-...` or
`$PD_PKI/.renew-client-...`. The previous private key is moved under
`history/openvpn/servers/<name>/` or `history/openvpn/clients/<name>/`.

### 6. Rotate Existing Identities

Rotation also issues a fresh certificate and archives the previous keypair, but
it revokes the archived certificate and refreshes the CRL.

```bash
nix run .#pd-ca -- rotate openvpn-server "$PD_PKI" ace
nix run .#pd-ca -- rotate openvpn-client "$PD_PKI" adam-laptop
```

Use rotation when the previous certificate must stop working as soon as the
replacement is issued. Like renewal, rotation leaves the replacement private key
in the normal `issued/` directory, but it is created first in a hidden
temporary workspace directory such as `$PD_PKI/.rotate-server-...` or
`$PD_PKI/.rotate-client-...`. The previous private key is moved into the
per-identity `history/` tree.

### 7. Revoke Without Replacing

Direct revocation retires the current certificate in place without creating a
replacement.

```bash
nix run .#pd-ca -- revoke openvpn-server "$PD_PKI" ace
nix run .#pd-ca -- revoke openvpn-client "$PD_PKI" adam-laptop
```

Use direct revoke when the identity should stop working and you are not rolling
out a replacement in the same step. Revocation does not create a new private
key or move the existing one.

### 8. Stage Deployable Host Material

Export just the material a single host needs:

```bash
nix run .#pd-ca -- stage openvpn-server "$PD_PKI" ace "$PWD/stage/ace"
nix run .#pd-ca -- stage openvpn-client "$PD_PKI" adam-laptop "$PWD/stage/adam-laptop"
```

Each staged tree contains the published bundles plus one identity subtree:

```text
stage/ace/
  bundles/
  issued/openvpn/servers/ace/

stage/adam-laptop/
  bundles/
  issued/openvpn/clients/adam-laptop/
```

The staged identity subtree is public-only. It contains the leaf certificate,
chain files, and metadata, but it does not include `<name>.key`.

When you install staged material onto an endpoint, provide the private key from
a separate local source such as endpoint state managed by `pd-openvpn-identity`.

## Lower-Level CA Primitives

These commands operate on explicit directories instead of the standard workspace
wrappers. They are useful when you need to build or inspect CA material by hand.
When you use them directly, you are responsible for any bundle publication
outside those explicit CA and identity directories.

### Initialize A Root CA In A Specific Directory

```bash
nix run .#pd-ca -- init-root \
  "$PD_PKI/authorities/root" \
  "Pseudo Design Root CA"
```

This creates the root private key at `"$PD_PKI/authorities/root/ca.key"`.

### Issue An Intermediate CA From A Parent Root

```bash
nix run .#pd-ca -- issue-intermediate \
  "$PD_PKI/authorities/root" \
  "Pseudo Design OpenVPN Intermediate CA" \
  "$PD_PKI/authorities/intermediate"
```

This creates the intermediate private key at
`"$PD_PKI/authorities/intermediate/ca.key"`.

### Issue A Leaf Certificate From A CA Directory

Server leaf:

```bash
nix run .#pd-ca -- issue-leaf \
  "$PD_PKI/authorities/intermediate" \
  openvpn-server \
  ace \
  "vpn.pseudo.design" \
  "$PD_PKI/issued/openvpn/servers/ace"
```

This creates the server private key at
`"$PD_PKI/issued/openvpn/servers/ace/ace.key"`.

Client leaf:

```bash
nix run .#pd-ca -- issue-leaf \
  "$PD_PKI/authorities/intermediate" \
  openvpn-client \
  adam-laptop \
  "adam-laptop" \
  "$PD_PKI/issued/openvpn/clients/adam-laptop"
```

This creates the client private key at
`"$PD_PKI/issued/openvpn/clients/adam-laptop/adam-laptop.key"`.

### Concatenate Certificate Chains Manually

`bundle-chain` concatenates certificate files in the order you provide them.

```bash
nix run .#pd-ca -- bundle-chain \
  "$PWD/openvpn-ca.crt" \
  "$PD_PKI/authorities/intermediate/ca.crt" \
  "$PD_PKI/authorities/root/ca.crt"
```

This is mainly useful for inspection or for rebuilding a public bundle outside
the higher-level workspace wrappers. It does not create or copy any private
keys.

## When To Prefer Which Layer

Use the workspace-oriented commands when you want:

* published `bundles/` output refreshed automatically
* OpenVPN server/client identities in the standard workspace layout
* automatic history tracking on renew and rotate
* CRL updates handled as part of rotate and revoke flows

Use the lower-level primitives when you want:

* explicit control over the CA and leaf output directories
* to inspect or repair part of the PKI layout manually
* to build certificate bundles outside the standard workspace wrappers

The broader PKI runbook, including `tls-crypt` handling and NixOS module
integration, lives in [pki-runbook.md](./pki-runbook.md).
