+++
title = "A two-node fleet with one source of truth"
description = "Reproducible NixOS systems that bind encrypted Raspberry Pi storage to device-held key material while preserving an explicit recovery and upgrade path."
date = 2026-08-26
draft = false
template = "case-study.html"

[extra]
order = 2
deliverable = "Encrypted Raspberry Pi 5 NixOS infrastructure"
repository_url = "https://github.com/PseudoDesign/nix-pseudo-design"
external_url = ""
+++

## Problem

Two Raspberry Pi 5 systems need repeatable installation and operation from NVMe storage without leaving the root filesystem unencrypted or depending on a portable key file. Host services and the public web surface also need to remain deployable from the same source of truth.

## Constraints

The storage key is derived from the board's OTP private key plus a per-install salt. Installation formats the target NVMe device, so key provisioning and salt placement must agree with the initrd that later unlocks the volume. Existing systems use a legacy HKDF derivation that cannot be replaced safely as an ordinary configuration change.

## Investigation

Hardware behavior, shared host policy, user access, and host-specific services were separated into focused NixOS modules. The disk-provisioning hook reads the same final derivation-scheme option as the installed system, avoiding a mismatch between the key used during formatting and the key reconstructed at boot.

## Delivered System

The flake exposes complete NixOS configurations for the `ace` and `mako` hosts. Shared Raspberry Pi 5 configuration covers NVMe boot, declarative disk layout, LUKS setup, OTP-derived unlocking, SSH policy, and reusable system defaults. The `mako` configuration composes separately packaged services with nginx virtual hosts and serves the Pseudo Design Zola build from an immutable Nix output.

## Demonstrated Result

Both host configurations are addressable as flake outputs and can be installed with `nixos-anywhere`. Provisioning stages a random salt during disk setup and installs it at the path consumed during boot. The site package validates its templates and links before nginx can serve the resulting static files.

## Handoff

The repository documents installation, OTP-key provisioning, local site builds, candidate deployment, production switching, and rollback. Encryption upgrades have a separate migration path: retain the existing scheme, enroll and test a recovery credential and a new keyslot, then change schemes only after a successful cold boot.
