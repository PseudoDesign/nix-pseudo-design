# PKI Runbook

This repository uses `pd-ca` as a software-backed certificate authority helper for OpenVPN.

The current design is:

* Root CA signs an intermediate CA.
* The intermediate CA issues OpenVPN server and client certificates.
* OpenVPN hosts consume the generated artifacts; they do not mint certificates themselves.

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
nix run .#pd-ca -- issue-openvpn-server "$PD_PKI" ace "vpn.pseudo.design"
```

Issue a client certificate:

```bash
nix run .#pd-ca -- issue-openvpn-client "$PD_PKI" adam-laptop "adam-laptop"
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

## Revoke Certificates

Revoke a server certificate:

```bash
nix run .#pd-ca -- revoke-openvpn-server "$PD_PKI" ace
```

Revoke a client certificate:

```bash
nix run .#pd-ca -- revoke-openvpn-client "$PD_PKI" adam-laptop
```

Revocation updates the intermediate CA state and refreshes `bundles/openvpn-ca.crl.pem`.

## Stage Host Material

To stage only the material a single host needs, export a deployable tree from the workspace.

Stage a server host tree:

```bash
nix run .#pd-ca -- stage-openvpn-server "$PD_PKI" ace "$PWD/stage/ace"
```

Stage a client host tree:

```bash
nix run .#pd-ca -- stage-openvpn-client "$PD_PKI" adam-laptop "$PWD/stage/adam-laptop"
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

This is the layout the OpenVPN NixOS modules consume directly.

## Consume Artifacts in NixOS

The OpenVPN modules can read the `pd-ca` workspace layout directly.

Server example:

```nix
{
  services.pdOpenvpnServer = {
    enable = true;
    vpnSubnet = "10.8.0.0";
    pki.bundleDir = "/run/secrets/openvpn/bundles";
    pki.identityDir = "/run/secrets/openvpn/issued/openvpn/servers/ace";
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
    pki.bundleDir = "/run/secrets/openvpn/bundles";
    pki.identityDir = "/run/secrets/openvpn/issued/openvpn/clients/adam-laptop";
    tlsCryptKeyFile = "/run/secrets/openvpn/tls-crypt.key";
    verifyX509Name = "vpn.pseudo.design";
  };
}
```

`pki.identityName` is optional and only needed when the certificate basename does not match the identity directory name.

## What To Treat As Secret

Do not commit these:

* `authorities/root/ca.key`
* `authorities/intermediate/ca.key`
* Any issued `*.key`
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
* add rotation and renewal workflows
