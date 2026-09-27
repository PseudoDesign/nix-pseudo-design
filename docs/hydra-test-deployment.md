# Hydra test deployment — 2026-09-27 UTC

This is the historical test-deployment baseline. See the
[live rollout report](hydra-live-rollout.md) for the subsequent persistent
switch, emergency-mode incident, recovery and successful kernel reboot.

The owner accepted the reviewed upgrade, then explicitly authorized merging the
three PRs and test-deploying Mako followed by Ace. Permanent switching and reboot
were excluded from that authorization. All three PRs are merged:

- `kaiba-infra` #2: `567d552e0cc65cf8a2473b7b922b287769f94307`.
- `kaiba-provisioning` #82: `9da2b998c021651321b6f25f3c38c68edf079aa8`.
- `nix-pseudo-design` #6: `0807232d74da575b12f9bfa5cd43bc9b788ebc39`.

## Running test configurations

The prebuilt closures were activated with `bin/switch-to-configuration test`,
the activation phase of `nixos-rebuild test`:

| Host | Running test closure |
| --- | --- |
| Ace | `/nix/store/66nynvy3zl94fr3q05ivkwyg4p1wl35g-nixos-system-ace-26.05.20260807.ee48b14` |
| Mako | `/nix/store/3snf55q7cp2mxwzqlhmxzsbcx3xpn450-nixos-system-mako-26.05.20260807.ee48b14` |

Their persistent `/nix/var/nix/profiles/system` links still point to the previous
generations recorded in the deployment review. No bootloader installation or
reboot occurred. Ace still runs kernel 6.12.47; the new 6.18 kernel is built but
has not booted. A reboot would return to the previous configuration until a
separately approved persistent switch.

Mako's activation completed cleanly. Ace's first activation returned status 4
with user-session and D-Bus errors during the systemd/D-Bus transition. SSH
authentication temporarily succeeded without opening command sessions. Access
recovered, all Hydra/PostgreSQL services started, and repeating the same test
activation completed with status 0. System and user failed-unit lists were empty
afterward. Both enrolled accounts and protected mounts retain their existing IDs
and state-file metadata; no pilot credential was read, copied or changed.

## Service acceptance

- `https://hydra.pseudo.design` serves Hydra with a valid Let's Encrypt
  certificate. HTTP-01 validation succeeded. HTTPS was checked through Mako's
  LAN address with the public hostname retained for certificate verification.
- Anonymous project viewing works; anonymous `/current-user` access is denied.
  Authenticated administrator login over HTTPS succeeds.
- `kaiba-infra/main` polls every 300 seconds. [Build 1](https://hydra.pseudo.design/build/1)
  succeeded using the existing test derivation from Ace's store. At 09:31 UTC,
  the next poll ran after 300 seconds and skipped unchanged inputs.
- `kaiba-provisioning/main` exists with polling disabled. No heavy jobs have run
  through live Hydra yet.
- Hydra's server restarted successfully and authenticated reconciliation still
  found the same administrator, projects and jobsets.
- Mako can reach Ace's port 3000; direct access from the deployment environment
  times out. The evaluator runs with `restrict-eval = true`. Scratch is on NVMe;
  the builder advertises one ARM64 build with the qualified feature set.
- A forced native KVM smoke rebuild passed under the new userspace and Nix
  daemon, with the old 6.12.47 kernel still running. Requalify after booting 6.18.
- `pseudo.design` and `crtvar.pseudo.design` returned HTTP 200 before and after.
  `dogsitting.pseudo.design` returned HTTP 502 before deployment and still does;
  that pre-existing application issue was not changed by this rollout.

## Credentials and backup

Hydra administrator `adam` has a randomly generated initial password in the
root-owned mode-0600 file `/var/lib/kaiba-hydra-bootstrap/adam-password` on Ace.
Retrieve it locally through the owner's existing SSH/sudo access and change it
through Hydra. Its contents were never printed, transferred to the deployment
environment, committed or stored in a Nix output.

The dedicated backup SSH private key remains on Ace. Mako holds only its public
key under the restricted rsync account; Ace pins Mako's verified host key.
The daily timer is scheduled for 03:00 UTC and retains seven dated snapshots.

The first backup service run succeeded. Checksums for the 2026-09-27 PostgreSQL
dump, Hydra state archive and generation record passed on both hosts. Restoring
the dump into the separate `hydra_restore_20260927` database recovered both
jobsets with the correct enablement, successful build 1 and the administrator
role. State archive extraction passed. The disposable restore database and
extracted directory were then removed; the live database was untouched.

## Correct firmware source before switching

Preflight found `/boot/firmware`'s automount inactive. Consequently, reading that
path exposed an older `/firmware` directory on the ESP (`nvme0n1p2`). That copy
disables Bluetooth/Wi-Fi and omits PCIe generation settings. It was the source
of the earlier firmware comparison.

The live device-tree bootloader `partition` property is 1. A separate read-only
mount of `disk-main-boot` (`nvme0n1p1`) confirmed the booted generation and kernel
links, with `dtparam=pciex1=on` and `dtparam=pciex1_gen=3`, and no Bluetooth/Wi-Fi
disable overlays. The follow-up hardware change preserves those actual boot
settings. The disk labels, mounts, legacy unlock recipe, candidate kernel and
initrd remain unchanged.

The corrected, built candidate is:

`/nix/store/6rq3psyd25v34jlj402agjs6vafdy5dg-nixos-system-ace-26.05.20260807.ee48b14`

It has not been activated or installed for boot. Use this corrected configuration
after its PR is reviewed; do not persist the earlier test candidate's firmware
settings. Both boot partitions' public files were archived separately under
`/var/backups/kaiba-hydra-rollout/before-5GpwHdbB` on Ace, with mode 0600 and
verified checksums. No pilot state, OTP private key or derived unlock key is
included. The temporary inspection mount was removed.

## Remaining rollout

Review and merge the firmware correction, arrange console/recovery access, then
authorize persistent switching and a controlled reboot. Verify disk unlock,
identity continuity and KVM on the new kernel before enabling provisioning's ten
jobs. Full job execution, a later main-commit trigger and live system rollback
remain acceptance work. Keep the previous generations and boot recovery archives
until that work is complete.
