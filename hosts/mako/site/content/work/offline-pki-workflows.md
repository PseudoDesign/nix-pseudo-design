+++
title = "Air-gapped PKI, made operable"
description = "Deterministic PKI contracts, signer tooling, and offline Raspberry Pi appliances for certificate operations that cross software, hardware, and human procedure."
date = 2026-05-21
draft = false
template = "case-study.html"

[extra]
order = 1
deliverable = "PKI workflow toolkit and offline CA appliances"
repository_url = "https://github.com/PseudoDesign/nix-pd-pki"
external_url = ""
+++

## Problem

Certificate operations span more than certificate generation. Root and intermediate authorities, VPN leaf credentials, hardware custody, removable-media transfers, revocation, and deployment all need to agree on the same workflow without turning live secrets into build artifacts.

## Constraints

Private-key custody and live certificate-authority state stay outside deterministic Nix derivations. The root workflow must operate offline, use YubiKeys and removable media, and remain legible to an operator during sensitive ceremonies. Runtime services still need validated certificates, chains, and revocation lists delivered through an external signing path.

## Investigation

The workflow was decomposed into four certificate roles and 19 ordered steps. Each step exposes machine-readable definitions, declared checks, implementation status, and representative public artifacts. That contract makes the boundary between reproducible reference material and mutable operational state explicit.

## Delivered System

The repository packages deterministic role contracts, NixOS modules, external signing tools, and an interactive removable-media operator. The tooling covers request export, external issuance, signed-result import, signer-side issuance state, revocation, and CRL generation. Raspberry Pi 5 images provide an offline root-CA launcher plus dedicated provisioning and intermediate-signing appliance variants.

## Demonstrated Result

Automated checks parse the generated data and validate X.509 certificates, CSRs, subject alternative names, extended key usage, and chains. Linux integration tests exercise a multi-node role topology and real OpenVPN server and client daemons, including rejection after a client certificate is added to a CRL.

## Handoff

The flake exposes packages, checks, modules, applications, appliance configurations, and the underlying role definitions across Linux and Darwin systems. Operator procedures and root ceremonies are documented alongside the implementation, while a report command collects check results as Markdown, JSON, HTML, and individual logs.
