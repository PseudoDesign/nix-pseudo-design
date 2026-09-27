# Hydra live rollout — 2026-09-27 UTC

The owner merged the firmware correction (#7, main revision
`93862b1bb76cd438555adaa710bc43a212c23680`) and subsequently authorized permanent
switching and a controlled Ace reboot. The configurations are now persistent:

| Host | Persistent system closure |
| --- | --- |
| Ace | `/nix/store/6rq3psyd25v34jlj402agjs6vafdy5dg-nixos-system-ace-26.05.20260807.ee48b14` |
| Mako | `/nix/store/3snf55q7cp2mxwzqlhmxzsbcx3xpn450-nixos-system-mako-26.05.20260807.ee48b14` |

Mako's switch completed cleanly. Its kernel and initrd were unchanged, so it was
not rebooted. Ace successfully rebooted into kernel 6.18.42 at 14:04 UTC after
the activation incident below. Its booted and current system links agree with
the persistent profile. No services were failed after reboot.

## Activation incident and recovery

At 09:57:18 UTC, Ace entered emergency mode during activation, before any reboot
was requested. The deployment script had started `boot-firmware.mount` directly
while `boot-firmware.automount` was inactive. The sysinit reactivation then tried
to start the automount over the mounted filesystem and failed:

```text
boot-firmware.automount: Path /boot/firmware is already a mount point, refusing start.
Dependency failed for Local File Systems.
local-fs.target: Triggering OnFailure= dependencies.
```

Systemd stopped networking and Hydra while isolating emergency mode. Boot-file
installation and the system-profile update had already completed, but the
deployment script was stopped before its final verification. The transient
unit's reported success was not evidence that the script completed.

The owner could not log into the recovery console; pressing Enter resumed the
default target at 14:00 UTC. SSH returned with the original boot ID and kernel
6.12.47, confirming this was an activation failure rather than a failed boot
into the new kernel. The protected pilot mount and public identity were intact.

Recovery started both automounts in order and accessed the corresponding paths.
With the deployment shell holding `/boot/firmware` as its working directory,
both automounts remained active. Repeating the installed candidate's
`switch-to-configuration test` completed with status 0 and no failed services.
The candidate kernel/initrd, firmware settings, retained old generation and
checksums of both pre-switch boot archives were verified before reboot.

## Required boot-mount preparation

Before activation or boot-file installation on Ace, enter a root shell and keep
it in the firmware directory through activation:

```sh
set -euo pipefail
systemctl start boot.automount
cd /boot
systemctl start boot-firmware.automount
cd /boot/firmware
systemctl is-active --quiet boot.automount
systemctl is-active --quiet boot-firmware.automount
test "$(findmnt -n -t vfat -o SOURCE --mountpoint /boot/firmware)" \
  = "$(readlink -f /dev/disk/by-partlabel/disk-main-boot)"
# Run the reviewed candidate's activation here, from this same shell.
```

Do not start the firmware mount directly while its automount is inactive. If a
mount already exists and prevents the automount from starting, stop and inspect
the mount state rather than continuing activation. The nested automount can
stop when the parent `/boot` mount idles out. Consequently, merely reading
`/boot/firmware` later can expose the stale directory on the ESP; always verify
the actual source partition. Mako uses different disk labels.

## Reboot acceptance

- Ace booted the persistent candidate, unlocked the existing encrypted root,
  mounted `/home`, and reported kernel 6.18.42 and no failed services.
- The complete public pilot status matched the pre-reboot snapshot, including
  enrollment, public-key digest and credential revision. The state directory
  remained UID 994/GID 988, mode 0700; `state.json` remained mode 0600 with one
  link. The bind mount retained `nosuid,nodev,noexec`. Swap remained disabled.
  No private credential or OTP-derived unlock key was read or transferred.
  The authenticated, read-only authority `self` request also succeeded. Mako's
  complete public pilot status was unchanged after its persistent switch.
- A forced rebuild of `kaiba-infra` revision
  `567d552e0cc65cf8a2473b7b922b287769f94307#packages.aarch64-linux.kvm-smoke-test`
  passed. The test asserts that QEMU reports KVM enabled and that the guest is
  ARM64. Its VM script completed in 18.45 seconds on the new kernel.
- PostgreSQL and all three principal Hydra services returned after reboot.
  HTTPS through Mako passed again after reboot with certificate verification.
- The authenticated setup command enabled `kaiba-provisioning/main` only after
  this qualification and the successful infrastructure build. Its first live
  evaluation started at 14:06:41 UTC.

## First provisioning evaluation

[Evaluation 2](https://hydra.pseudo.design/eval/2) resolved provisioning `main`
to `9da2b998c021651321b6f25f3c38c68edf079aa8`. Its jobs exactly matched the
ten-item infrastructure inventory, all with system `aarch64-linux`. All ten
finished successfully; the queue-runner journal explicitly records each as
cached. The results were downloaded from the configured signed provisioning
cache, rather than freshly executed on Ace.

| Check | Successful Hydra build |
| --- | --- |
| copied-storage-vm | [2](https://hydra.pseudo.design/build/2) |
| device-secret-execution-vm | [3](https://hydra.pseudo.design/build/3) |
| device-secret-offline-storage-vm | [4](https://hydra.pseudo.design/build/4) |
| device-secret-storage-development-vm | [5](https://hydra.pseudo.design/build/5) |
| device-secret-target-artifacts | [6](https://hydra.pseudo.design/build/6) |
| device-secret-target-luks-vm | [7](https://hydra.pseudo.design/build/7) |
| enrollment-storage-vm | [8](https://hydra.pseudo.design/build/8) |
| stable-campaign-provisioner-unsigned-artifacts | [9](https://hydra.pseudo.design/build/9) |
| stable-handoff-aarch64-kexec-file-vm | [10](https://hydra.pseudo.design/build/10) |
| stable-verifier-aarch64-kexec-vm | [11](https://hydra.pseudo.design/build/11) |

This establishes live restricted evaluation, separate job reporting and cache
reuse. The fresh native KVM execution evidence is the smoke test above; these
cached results do not establish the execution mode of each provisioning VM on
Ace. Fresh full-suite execution, an evaluation triggered by a later `main`
commit and live failure reporting still require observation. Both jobsets now
poll their own repository's `main` every 300 seconds.

## Backup after recovery

The daily backup service ran successfully again after reboot, and checksums
passed on Ace and Mako. Daily snapshots are immutable: repeated runs on the
same UTC day preserve the first completed snapshot. The 2026-09-27 copy therefore
still contains the initial infrastructure stage, with provisioning disabled and
one successful build. A second restore into a disposable database confirmed
that state and the administrator role; the disposable database was removed.
It is not a snapshot of the later ten-build evaluation. The next daily run is
03:00 UTC on 2026-09-28. After restoring the earlier snapshot, reconcile with
`setup_hydra.py --stage provisioning --apply` once host qualification is confirmed.

## Retained recovery material

Ace's old working system remains GC-rooted and installed as `nixos/3-default`;
generation 2 is an unrelated provisioner and must not be selected as the host
rollback. Both boot recovery archives remain under
`/var/backups/kaiba-hydra-rollout/before-5GpwHdbB`. Mako's pre-switch firmware
archive is under `/var/backups/kaiba-hydra-rollout/before-8Mfw5pjc`. A live system
rollback has not been exercised. The successful reboot does not establish the
pilot protocol's separate `full_qualification` property.
