# PKI Runbook

This repository uses `pd-ca` as a software-backed certificate authority helper for OpenVPN.

For a command-by-command guide aimed at operators running `pd-ca` directly, see
[pd-ca-manual.md](./pd-ca-manual.md).

The current design is:

* Root CA signs an intermediate CA.
* The intermediate CA issues OpenVPN server and client certificates.
* OpenVPN hosts consume the generated artifacts; they do not mint certificates themselves.

The workspace-oriented `pd-ca` CLI uses a verb plus profile form such as
`issue openvpn-server ...` or `rotate openvpn-client ...`.

YubiKey-backed root signing can be added later without changing the host-facing artifact layout.

## Workspace Location

Keep the CA workspace outside Git. It contains private keys, issued private keys, revocation state, and issuance history.

Example:

```bash
export PD_PKI="$HOME/.local/share/pseudo-design/pki"
mkdir -p "$PD_PKI"
```

## Bootstrap a Workspace

Initialize the root CA once:

```bash
nix run .#pd-ca -- init-root-ca "$PD_PKI" "Pseudo Design Root CA"
```

Initialize the OpenVPN intermediate once:

```bash
nix run .#pd-ca -- init-intermediate-ca "$PD_PKI" "Pseudo Design OpenVPN Intermediate CA"
```

After those two commands, the workspace contains a layout like:

```text
$PD_PKI/
  authorities/
    root/
    intermediate/
  issued/
    openvpn/
      servers/
      clients/
  bundles/
    root-ca.crt
    intermediate-ca.crt
    openvpn-ca.crt
    openvpn-ca.crl.pem
```

The `bundles/` directory is the stable public-consumer interface:

* `openvpn-ca.crt` is the trust chain for OpenVPN peers.
* `openvpn-ca.crl.pem` is the current CRL for revoked OpenVPN certificates.

## Issue Certificates

Issue a server certificate:

```bash
nix run .#pd-ca -- issue openvpn-server "$PD_PKI" ace "vpn.pseudo.design"
```

Issue a client certificate:

```bash
nix run .#pd-ca -- issue openvpn-client "$PD_PKI" adam-laptop "adam-laptop"
```

Issued identities land here:

```text
$PD_PKI/issued/openvpn/servers/ace/
$PD_PKI/issued/openvpn/clients/adam-laptop/
```

Each issued identity directory contains:

* `<name>.crt`
* `<name>.key`
* `ca-chain.crt`
* `full-chain.crt`
* `common-name`
* `profile`

## Renew And Rotate

Renewal issues a fresh certificate for the same logical identity and archives the previous material under the workspace history tree. It does not revoke the archived certificate.

Renew a server certificate:

```bash
nix run .#pd-ca -- renew openvpn-server "$PD_PKI" ace
```

Renew a client certificate:

```bash
nix run .#pd-ca -- renew openvpn-client "$PD_PKI" adam-laptop
```

Rotation issues a fresh certificate, archives the previous material, and revokes the archived certificate so the CRL starts rejecting it.

Rotate a server certificate:

```bash
nix run .#pd-ca -- rotate openvpn-server "$PD_PKI" ace
```

Rotate a client certificate:

```bash
nix run .#pd-ca -- rotate openvpn-client "$PD_PKI" adam-laptop
```

Archived material is kept here:

```text
$PD_PKI/history/openvpn/servers/ace/
$PD_PKI/history/openvpn/clients/adam-laptop/
```

Each archived entry is named with a UTC timestamp and the archived certificate serial.

## Revoke Certificates

Revoke a server certificate:

```bash
nix run .#pd-ca -- revoke openvpn-server "$PD_PKI" ace
```

Revoke a client certificate:

```bash
nix run .#pd-ca -- revoke openvpn-client "$PD_PKI" adam-laptop
```

Revocation updates the intermediate CA state and refreshes `bundles/openvpn-ca.crl.pem`.

Use direct revoke when you want to retire the current certificate without issuing a replacement. Use rotate when you want replacement and revocation as one operation.

## Stage Host Material

To stage only the material a single host needs, export a deployable tree from the workspace.

Stage a server host tree:

```bash
nix run .#pd-ca -- stage openvpn-server "$PD_PKI" ace "$PWD/stage/ace"
```

Stage a client host tree:

```bash
nix run .#pd-ca -- stage openvpn-client "$PD_PKI" adam-laptop "$PWD/stage/adam-laptop"
```

Each staged tree contains:

```text
stage/ace/
  bundles/
  issued/openvpn/servers/ace/

stage/adam-laptop/
  bundles/
  issued/openvpn/clients/adam-laptop/
```

The staged tree contains only public CA and certificate material. It does not
include `<name>.key`.

This is the public side of the layout the OpenVPN NixOS modules consume.

## Endpoint-Local Identity State

Use `pd-openvpn-identity` on the endpoint that owns the OpenVPN private key.
The helper keeps endpoint-local `active/`, `pending/`, and `history/`
directories outside the CA workspace.

A transitional import flow looks like:

```bash
export PD_OPENVPN_IDENTITIES="$HOME/.local/share/pseudo-design/openvpn/identities"
install -d -m 0700 "$PD_OPENVPN_IDENTITIES"

nix run .#pd-openvpn-identity -- import-active \
  "$PD_OPENVPN_IDENTITIES/adam-laptop" \
  "/var/lib/pseudo-design/private/adam-laptop.key" \
  "$PWD/stage/adam-laptop/issued/openvpn/clients/adam-laptop"
```

That creates an endpoint-local state tree such as:

```text
$PD_OPENVPN_IDENTITIES/adam-laptop/
  active/
    adam-laptop.key
    adam-laptop.crt
    ca-chain.crt
    full-chain.crt
  pending/
  history/
```

`init-server`, `init-client`, `prepare-server-rekey`, and
`prepare-client-rekey` are available for the future CSR-driven flow. Today, the
important operational point is that the endpoint key should come from local
state rather than from the staged `pd-ca` tree.

## Generate the Shared tls-crypt Key

The `tls-crypt` key is separate from the certificate-authority workspace. Generate it once, keep it outside Git, and distribute the same file to every OpenVPN server and client that should participate in the deployment:

```bash
install -d -m 0700 "$HOME/.local/share/pseudo-design/openvpn"
nix run .#pd-openvpn-generate-tls-crypt-key -- \
  "$HOME/.local/share/pseudo-design/openvpn/tls-crypt.key"
```

Treat that file like other private key material. If you need to replace it, generate a new one and roll it out to every OpenVPN peer before switching configurations over to the new path or contents.

## Install Staged Trees At Runtime

When a host should copy a staged tree into `/run/secrets` on boot, point the OpenVPN module at the staged root:

Server example:

```nix
{
  services.pdOpenvpnServer = {
    enable = true;
    vpnSubnet = "10.8.0.0";
    clientToClient = true;
    pki.install = {
      sourceDir = "/var/lib/pseudo-design/stage/ace";
      identityKeySourceFile = "/var/lib/pseudo-design/openvpn/identities/ace/active/ace.key";
      tlsCryptSourceFile = "/var/lib/pseudo-design/openvpn/tls-crypt.key";
    };
  };
}
```

Client example:

```nix
{
  services.pdOpenvpnClient = {
    enable = true;
    remoteHost = "vpn.pseudo.design";
    pki.install = {
      sourceDir = "/var/lib/pseudo-design/stage/adam-laptop";
      identityKeySourceFile = "/var/lib/pseudo-design/openvpn/identities/adam-laptop/active/adam-laptop.key";
      tlsCryptSourceFile = "/var/lib/pseudo-design/openvpn/tls-crypt.key";
    };
    verifyX509Name = "vpn.pseudo.design";
  };
}
```

With the default settings, the module installs the staged tree into `/run/secrets/openvpn/<instanceName>` before each `openvpn-<instanceName>.service` start and derives `pki.bundleDir` plus `pki.identityDir` from that runtime location.

`pki.install.identityKeySourceFile` is required for install mode and is copied
into the installed identity directory as `<name>.key`.

If `pki.install.tlsCryptSourceFile` is set, the module also copies that shared key into the same runtime directory and defaults `tlsCryptKeyFile` to `/run/secrets/openvpn/<instanceName>/tls-crypt.key`. The staged `pd-ca` tree itself still contains only CA and certificate material.

Set `clientToClient = true;` on the server when connected VPN peers should be able to talk to each other directly through the OpenVPN daemon, such as a host-to-host management overlay.

## Consume Artifacts In Place In NixOS

The OpenVPN modules can read the `pd-ca` workspace layout directly.

Server example:

```nix
{
  services.pdOpenvpnServer = {
    enable = true;
    vpnSubnet = "10.8.0.0";
    clientToClient = true;
    pki.bundleDir = "/var/lib/pseudo-design/pki/bundles";
    pki.identityDir = "/var/lib/pseudo-design/openvpn/identities/ace/active";
    pki.identityName = "ace";
    tlsCryptKeyFile = "/run/secrets/openvpn/tls-crypt.key";
  };
}
```

Client example:

```nix
{
  services.pdOpenvpnClient = {
    enable = true;
    remoteHost = "vpn.pseudo.design";
    pki.bundleDir = "/var/lib/pseudo-design/pki/bundles";
    pki.identityDir = "/var/lib/pseudo-design/openvpn/identities/adam-laptop/active";
    pki.identityName = "adam-laptop";
    tlsCryptKeyFile = "/run/secrets/openvpn/tls-crypt.key";
    verifyX509Name = "vpn.pseudo.design";
  };
}
```

`pki.identityName` is optional when the identity directory basename already
matches the certificate basename. It is required when pointing at an endpoint
state directory such as `.../active`.

## What To Treat As Secret

Do not commit these:

* `authorities/root/ca.key`
* `authorities/intermediate/ca.key`
* Any issued `*.key`
* Any endpoint-local `active/*.key` or `pending/*/*.key`
* The CA workspace as a whole

Usually safe to distribute to OpenVPN consumers:

* `bundles/openvpn-ca.crt`
* `bundles/openvpn-ca.crl.pem`
* Issued `*.crt`

## Current Boundaries

This runbook covers the software-backed CA flow only.

Future work:

* swap the root signer to hardware-backed signing
* add artifact distribution to hosts
