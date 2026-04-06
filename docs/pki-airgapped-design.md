# Airgapped PKI Design

This document describes the target PKI design for an airgapped root signer,
an operational intermediate signer, and endpoint-owned OpenVPN leaf keys.

This is a design target, not the current implementation.

## Goals

* The root private key exists only on the root signing machine.
* The intermediate private key exists only on the intermediate signing machine.
* Each OpenVPN endpoint private key exists only on the device that uses it.
* All workflows operate through explicit request and response packages.
* No command requires network reachability between root, intermediate, or endpoints.

## Roles

### Root Signer

Responsibilities:

* Own the root CA key.
* Sign or revoke intermediate CA certificates.
* Export root public material for the intermediate signer.

Front-end CLI:

* `pd-root-ca`

### Intermediate Signer

Responsibilities:

* Own the intermediate CA key.
* Sign, renew, rotate, or revoke OpenVPN server and client certificates.
* Export public cert and bundle material for endpoints.

Front-end CLI:

* `pd-intermediate-ca`

### Endpoint

Responsibilities:

* Generate and keep its own OpenVPN private key.
* Generate CSRs locally.
* Install signed response packages from the intermediate signer.

Front-end CLI:

* `pd-openvpn-identity`

## Root State Layout

`ROOT_STATE_DIR` is fully self-contained:

```text
ROOT_STATE_DIR/
  ca/
    ca.key
    ca.crt
    ca-chain.crt
    ca.crl.pem
    serial
    crlnumber
    index.txt
    index.txt.attr
    common-name
    role
    issued/
      certs/
      records.tsv
    revoked/
      certs/
      records.tsv
  bundles/
    root-ca.crt
    root-ca.crl.pem
  inbox/
    intermediate/
  outbox/
    intermediate/
  archive/
    requests/
    responses/
```

Rules:

* Only the root machine contains `ca/ca.key`.
* The root never processes endpoint leaf requests.

## Intermediate State Layout

`INTERMEDIATE_STATE_DIR` is fully self-contained once bootstrapped:

```text
INTERMEDIATE_STATE_DIR/
  ca/
    ca.key
    ca.csr
    ca.crt
    issuer-chain.crt
    ca-chain.crt
    ca.crl.pem
    serial
    crlnumber
    index.txt
    index.txt.attr
    common-name
    role
    issued/
      certs/
      records.tsv
    revoked/
      certs/
      records.tsv
  issuer/
    root-ca.crt
    root-ca.crl.pem
  bundles/
    openvpn-ca.crt
    openvpn-ca.crl.pem
  issued/
    openvpn/
      servers/
        <name>/
          <name>.crt
          ca-chain.crt
          full-chain.crt
          common-name
          profile
      clients/
        <name>/
          <name>.crt
          ca-chain.crt
          full-chain.crt
          common-name
          profile
  history/
    openvpn/
      servers/
        <name>/
          <timestamp>-<serial>/
            <name>.crt
            ca-chain.crt
            full-chain.crt
            common-name
            profile
      clients/
        <name>/
          <timestamp>-<serial>/
            <name>.crt
            ca-chain.crt
            full-chain.crt
            common-name
            profile
  inbox/
    openvpn/
  outbox/
    openvpn/
  archive/
    requests/
    responses/
```

Rules:

* Only the intermediate machine contains `ca/ca.key`.
* No leaf private keys appear anywhere in this tree.
* `issued/` and `history/` contain cert-only records and metadata.

## Endpoint State Layout

`IDENTITY_DIR` separates active and pending state:

```text
IDENTITY_DIR/
  identity-name
  common-name
  profile
  active/
    <name>.key
    <name>.crt
    ca-chain.crt
    full-chain.crt
    common-name
    profile
    installed-request-id
  pending/
    <request-id>/
      <name>.key
      <name>.csr
      common-name
      profile
      request-kind
      created-at
  history/
    <timestamp>-<serial>/
      <name>.key
      <name>.crt
      ca-chain.crt
      full-chain.crt
      common-name
      profile
```

Rules:

* The endpoint is the only place that stores its leaf private key.
* `active/` is the material OpenVPN should consume.
* `pending/` is for local rekeys before a signed response is installed.

## Transfer Package Format

Every transferred package is a directory that can also be tarred as-is:

```text
PACKAGE_DIR/
  manifest.json
  SHA256SUMS
  payload/...
```

`manifest.json` contains:

* `formatVersion`
* `packageType`
* `requestId`
* `createdAt`
* `name`
* `commonName`
* `profile`
* `requestKind`
* `sourceHost`

## Intermediate CA Request Package

Created on the intermediate signer and consumed by the root signer.

```text
payload/
  ca.csr
```

`packageType = "intermediate-ca-request"`

## Intermediate CA Response Package

Created on the root signer and consumed by the intermediate signer.

```text
payload/
  ca/
    ca.crt
    issuer-chain.crt
    ca-chain.crt
  bundles/
    root-ca.crt
    root-ca.crl.pem
```

`packageType = "intermediate-ca-response"`

## OpenVPN Leaf Request Package

Created on an endpoint and consumed by the intermediate signer.

```text
payload/
  identity.csr
  current.crt
```

`current.crt` is optional and is included for renew and rotate requests.

`packageType = "openvpn-leaf-request"`

`requestKind` values:

* `issue`
* `renew`
* `rotate`

## OpenVPN Leaf Response Package

Created on the intermediate signer and consumed by an endpoint.

```text
payload/
  identity/
    <name>.crt
    ca-chain.crt
    full-chain.crt
    common-name
    profile
  bundles/
    openvpn-ca.crt
    openvpn-ca.crl.pem
```

`packageType = "openvpn-leaf-response"`

No response package contains a leaf private key.

## Command Surface

### Root Signer Commands

* `pd-root-ca init STATE_DIR COMMON_NAME`
* `pd-root-ca sign-intermediate-request STATE_DIR REQUEST_DIR OUT_DIR`
* `pd-root-ca revoke-intermediate STATE_DIR NAME`
* `pd-root-ca export-root-bundle STATE_DIR OUT_DIR`
* `pd-root-ca show STATE_DIR`

### Intermediate Signer Commands

* `pd-intermediate-ca init STATE_DIR COMMON_NAME OUT_REQUEST_DIR`
* `pd-intermediate-ca install-root-response STATE_DIR RESPONSE_DIR`
* `pd-intermediate-ca sign-openvpn-server-request STATE_DIR REQUEST_DIR OUT_DIR`
* `pd-intermediate-ca sign-openvpn-client-request STATE_DIR REQUEST_DIR OUT_DIR`
* `pd-intermediate-ca renew-openvpn-server-request STATE_DIR REQUEST_DIR OUT_DIR`
* `pd-intermediate-ca renew-openvpn-client-request STATE_DIR REQUEST_DIR OUT_DIR`
* `pd-intermediate-ca rotate-openvpn-server-request STATE_DIR REQUEST_DIR OUT_DIR`
* `pd-intermediate-ca rotate-openvpn-client-request STATE_DIR REQUEST_DIR OUT_DIR`
* `pd-intermediate-ca revoke-openvpn-server STATE_DIR NAME`
* `pd-intermediate-ca revoke-openvpn-client STATE_DIR NAME`
* `pd-intermediate-ca export-openvpn-bundles STATE_DIR OUT_DIR`
* `pd-intermediate-ca export-openvpn-server-response STATE_DIR NAME OUT_DIR`
* `pd-intermediate-ca export-openvpn-client-response STATE_DIR NAME OUT_DIR`
* `pd-intermediate-ca show STATE_DIR`

### Endpoint Commands

* `pd-openvpn-identity init-server IDENTITY_DIR NAME COMMON_NAME OUT_REQUEST_DIR`
* `pd-openvpn-identity init-client IDENTITY_DIR NAME COMMON_NAME OUT_REQUEST_DIR`
* `pd-openvpn-identity prepare-server-rekey IDENTITY_DIR NAME COMMON_NAME OUT_REQUEST_DIR`
* `pd-openvpn-identity prepare-client-rekey IDENTITY_DIR NAME COMMON_NAME OUT_REQUEST_DIR`
* `pd-openvpn-identity install-server-response IDENTITY_DIR RESPONSE_DIR`
* `pd-openvpn-identity install-client-response IDENTITY_DIR RESPONSE_DIR`
* `pd-openvpn-identity show IDENTITY_DIR`

## Invariants

* Root key only on the root signer.
* Intermediate key only on the intermediate signer.
* Leaf key only on the owning endpoint.
* Transfer packages contain no private keys.
* Root never handles leaf requests.
* Intermediate never handles root private material.
