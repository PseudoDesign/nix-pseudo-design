# Hydra deployment review — 2026-09-27 UTC

The implementation is built and tested, but neither host has been activated.
Ace's current upstream configuration differed from its installed storage and
boot recipe. The host-specific configuration now preserves the installed layout;
the remaining OS upgrade still needs a reviewed deployment window.

## Qualification

Ace has 16 GB RAM, no swap, and an encrypted NVMe root filesystem with about
40 GiB free after building candidates (56 GiB before qualification builds).
Its separate `/home` logical volume remains mounted. Native ARM64 VM qualification
passed with QEMU reporting KVM enabled inside the Nix build environment. The
Hydra/PostgreSQL integration VMs passed authenticated, repeatable setup,
restricted evaluation, restart persistence, backup transfer and restoration,
and rejection of shell access by the backup account.

The corrected legacy helper passed both a synthetic byte-compatibility test and
`cryptsetup open --test-passphrase` against Ace's existing LUKS volume. The real
key was consumed through a pipe entirely on Ace; it was not printed, persisted,
returned to the deployment machine, or added to Nix outputs. This validates the
recipe on the running kernel, not a reboot into the proposed kernel.

The pilot state remains UID 994/GID 988, directory mode 0700, single-link state
file mode 0600, and an active `rw,nosuid,nodev,noexec` self-bind mount. The
credential was not read, copied, regenerated, or re-enrolled.

## Preserved storage

Ace uses `disk-main-luks`, `disk-main-boot` and `disk-main-ESP`, with separate
`pool-rootfs` and `pool-home` logical volumes. It must not use Mako's shared
fresh-install `disk-nvme0-luks-*` disko layout. Ace now has a dedicated hardware
module with those existing labels, `/boot`, `/boot/firmware` and `/home` mounts,
no swap, and the existing direct Raspberry Pi kernel bootloader.

Its running key recipe hashes the literal `default-salt`, the old OTP helper's
text output, and a newline with SHA-256. This predates the upstream
`legacy-hkdf-v1` scheme; selecting that scheme or generating a new random salt
would not preserve this installation's key. The compatibility helper retains
the actual recipe. Future key-scheme migration is a separate operation.

Mako's existing disk labels and mounts match the shared hardware module. Its
kernel and initrd remain unchanged by this rollout.

## System changes to approve

| Component | Running Ace | Proposed Ace |
| --- | --- | --- |
| NixOS | 25.11.20260313.3e20095 | 26.05.20260807.ee48b14 |
| Kernel | 6.12.47-stable_20250916 | 6.18.42-unstable_20260806 |
| Nix | 2.31.2 | 2.34.8 |
| systemd | 258.3 | 260.2 |
| glibc | 2.40-218 | 2.42-67 |

Firmware and initrd also change. Current upstream no longer includes Ace's
system-level Home Manager activation, nix-ld or pcscd configuration. Those
removals are part of the closure comparison and must be considered explicitly;
this rollout does not claim they are unrelated or harmless.

The full package comparisons are [Ace](hydra-rollout/ace-closure-diff.txt) and
[Mako](hydra-rollout/mako-closure-diff.txt). Mako's changes are limited to the
Hydra ACME/proxy and backup receiver dependencies. Its existing application
packages, kernel and initrd are unchanged.

## Built candidates

These exact closures were built on Ace and match local evaluation:

- Ace: `/nix/store/66nynvy3zl94fr3q05ivkwyg4p1wl35g-nixos-system-ace-26.05.20260807.ee48b14`
- Mako: `/nix/store/7xq7faj7msr14xrj9hmdpnyjmfpk8815-nixos-system-mako-26.05.20260807.ee48b14`

The final Ace initrd was inspected for the legacy helper, OTP helper and
`vcgencmd`; shell-script dependencies are included explicitly.

## Deployment and recovery sequence

1. Merge the three reviewed PRs after their checks pass. Both Hydra jobsets
   intentionally track `main`, not the draft branches.
2. Record and GC-root both running generations before enabling scheduled GC:
   - Ace: `/nix/store/n4z60a804j4irva6qjy46qh0bdq3pl2v-nixos-system-ace-25.11.20260313.3e20095`
   - Mako: `/nix/store/hb6b4iji0ljrcr778y8qb7rfyh2hss1w-nixos-system-mako-26.05.20260807.ee48b14`
3. Save Ace's public boot files as a root-only recovery archive on Ace, and
   ensure console/recovery access is available before changing its boot files.
   Do not archive the pilot state, OTP private key or a derived unlock key.
4. Use `nixos-rebuild test` for Mako, then Ace. Verify existing applications,
   pilot mount metadata, PostgreSQL, Hydra, HTTPS and source-restricted port 3000.
   A test activation does not install a new boot entry. If it fails, run the
   recorded old generation's `bin/switch-to-configuration test` on that host.
5. Create the runtime-only administrator and backup SSH credentials. Reconcile
   the infrastructure stage, obtain a successful Hydra infrastructure build,
   and test backup restoration into a separate database.
6. Persist with `switch` only after service acceptance and approval of the
   boot/recovery changes. Restore the previous system profile and run its
   `bin/switch-to-configuration switch` if persistent rollback is needed.
   Do not roll back a migrated Hydra database without a matching snapshot.
7. A physical boot into the new kernel, its disk-unlock path and KVM must be
   qualified with recovery access available. Keep the heavy jobset disabled
   until these prerequisites and the infrastructure build are satisfied; then
   enable and verify all ten jobs, subsequent main polling and output reuse.

Live HTTPS, administrator bootstrap, live backup restoration, full ten-job Hydra
execution, main-commit triggering, system rollback and reboot acceptance remain
pending. The successful VM tests do not substitute for those live checks.
