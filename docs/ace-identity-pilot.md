# Persistent SPIRE identity pilot on Ace

The owner selected `pilot.kaiba.pseudo.design` for this pilot. Ace adds a
standalone, loopback-only SPIRE authority and a local agent. This installation
does not require the trust-domain name to resolve in DNS. Public DNS publication
and fleet inventory authorization remain separate integration steps.

The first registered workload is a dedicated health probe. Its logical device
is `ace`, and its instance is `ace-pilot-20260929`. These are identifiers for
this identity pilot, not an activation or replacement of Ace's existing enrolled
device credential. The existing pilot account, Hydra, PostgreSQL and human SSH
access must be preserved.

## Source and initialization

`hosts/ace/identity-pilot.nix` imports Fleet's opt-in persistent pilot module.
The Fleet input pins the identity runtime independently of the host's existing
kernel, initrd and application packages. Keep the chosen trust domain and
instance stable after initialization.

Services remain uninitialized until the operator explicitly runs:

```sh
sudo systemctl start kaiba-identity-pilot-initialize.service
```

Run this only after reviewing and activating the candidate and confirming that
there is no pre-existing SPIRE authority to adopt. Initialization must reject
existing or partial state. Do not remove state or repeat initialization to
work around a failed check.

The server database and signing keys live under `/var/lib/kaiba/identity/server`,
the local agent state under `/var/lib/kaiba/identity/local`, and the durable
bootstrap manifest and authenticated bundle under
`/var/lib/kaiba/identity/pilot-bootstrap`. Never put bootstrap grants, private
keys or database contents in the repository, Nix store or deployment logs.
Initial admission uses a short-lived grant removed after successful attestation.
The health probe requires both its dedicated Unix identity and exact systemd
unit; running the same executable as that user in another unit is insufficient.

## Deployment checks

The baseline source is `8ec7763670d0d4722162251cc4eb2f5e00432b54`; its tree
matches the previously deployed `9264275` host branch. The measured pre-change
current and persistent system is:

```text
/nix/store/f4q82s6kzy6y4q943y9v9nsm64c9s0xp-nixos-system-ace-26.05.20260807.ee48b14
```

Before activation, compare the complete closure difference and require the
candidate's kernel, initrd, kernel modules, fstab, disk-unlock configuration,
Hydra/PostgreSQL/SSH units and existing pilot protected mount to match that
baseline. Ace uses its dedicated pre-HKDF unlock helper and existing partition
labels; the shared fresh-install hardware module is not a replacement.

Use the held-automount procedure in [the live rollout notes](hydra-live-rollout.md#required-boot-mount-preparation)
for both `switch-to-configuration test` and `switch`. Directly starting the
firmware mount previously caused emergency mode. Preserve the current system
as the rollback target; older generations may predate the `/home` migration.
The [activation helper](../scripts/activate-ace-identity-pilot.sh) enforces the
boot and existing-service comparisons, roots the previous system for recovery,
and holds both automounts through activation. Run it as root on Ace with the
reviewed candidate path, previous path, and `test` or `switch`. It updates the
persistent system profile only for `switch`. If activation fails, inspect the
failure and restore the previous profile and configuration with the same mount
procedure before proceeding; never reset identity state as a rollback step.

After test activation and initialization, verify:

- SPIRE server and agent are healthy, with only a loopback authority listener.
- The exact health-probe unit obtains the expected SPIFFE identity.
- Another unit running as the probe user is denied.
- The consumed grant is absent and server/agent restart retains the authority,
  node identity and workload registration.
- Existing Hydra/PostgreSQL/SSH services and pilot mount remain healthy.

Only then make the generation persistent using the same guarded `switch`
procedure. A successful switch is not evidence of a reboot. Keep real-host
reboot observations distinct from VM restart and reboot checks.

## Recovery and limits

To roll back the software, stop the pilot timer and services and reactivate
the recorded previous system with the guarded mount procedure. Preserve the
new authority state. Restoring an older authority database or rerunning
initialization can undo security decisions or create a different authority;
neither is an ordinary software rollback.

The agent uses `rebootstrap_mode = "never"`. With the current one-hour node
credential lifetime, prolonged downtime may require explicit recovery. This
pilot requires the host time service to report synchronization at startup; it
does not establish indefinite offline startup, protected clock behavior,
hardware key isolation, state rollback protection or production admission.
No firmware, OTP, TPM, disk formatting or existing enrolled key change is part
of this installation.

## Deployment result — 2026-09-29 UTC

Ace now runs persistent generation **10**, built from Fleet revision
`c7d13f8ecd3e8d98108a2c6eb4787c550405e7c2`:

```text
/nix/store/ylpbjk8jzr195l7yn7f713sgjfimicbs-nixos-system-ace-26.05.20260807.ee48b14
```

The locked published source reproduces the tested native ARM64 build exactly.
Both guarded activation phases passed. The previous system remains GC-rooted
at `/nix/var/nix/gcroots/kaiba-identity-pilot-before`, and generation 9 remains
available in the boot configuration. Mako's evaluated system is unchanged.

The [sanitized observation](observations/2026-09-29-ace-identity-pilot.json)
records fresh SSH verification at `2026-09-29T06:09:10Z`. The intended unit
obtained the exact identity below; another unit using the same Unix user was
denied, and that user could not read authority keys or access the admin socket.
Restarting both SPIRE services without the consumed grant retained the bundle,
node identity and workload registration. The five-minute probe timer is active.

```text
spiffe://pilot.kaiba.pseudo.design/device/ace/instance/ace-pilot-20260929/workload/identity-probe
```

Kernel, initrd, kernel modules, fstab, crypttab and existing service definitions
matched the recorded baseline. The existing client's public enrollment status
remained identical, Hydra/PostgreSQL/SSH remained healthy, and no units were
failed after activation. Ordinary boot-file installation selected the new
generation; no EEPROM, OTP, disk layout or unlock recipe was changed.

Fleet's two module evaluations and all ten VM acceptance groups pass, including
fresh VM startup with retained disk, live-source rotation, interrupted-init
cleanup, clean SQLite restart, missing-state refusal and bundle restoration.
The hardware checks use the normal one-hour lifetime and a one-shot probe;
they do not repeat the VM's short-TTL rotation scenario.

Ace was **not rebooted** for the initial installation. Its original receipt
retains that historical result. The subsequent warm reboot below is separate
evidence; offline time and rollback qualification, complete fleet admission,
and public DNS remain next steps.

## Subsequent warm reboot — 2026-09-29 UTC

After verifying the installed boot kernel and initrd against generation 10,
the operator requested a controlled warm reboot at `06:42:40Z`. The
[separate warm-reboot receipt](observations/2026-09-29-ace-identity-warm-reboot.json)
records all eleven before/after checks passing with the provisioning
[read-only observer](https://github.com/PseudoDesign/kaiba-provisioning/blob/80edf573aadbca788df2c547dfaf3f96ad37e6a8/scripts/offline-qualification/observe_reboot.py).
The healthy baseline was captured at `06:40:48Z`; the ready post-reboot capture
at `06:44:11Z` reported 77.15 seconds of uptime. Current, persistent and booted
system links all pointed to the generation-10 closure recorded above.

The boot ID and completed probe invocation changed, while the exact SPIFFE URI,
trust-bundle digest and complete canonical public enrollment-status digest
remained unchanged. The current-boot probe obtained an unexpired credential;
the consumed grant remained absent, existing pilot metadata/mount protections
passed, all eight checked identity/infrastructure services were active and
no units were failed. Time synchronization and identity startup converged
automatically. No identity-service, probe, or clock start was performed manually
after the reboot request.

An early capture at `06:43:29Z`, 35.24 seconds into the new boot, was correctly
rejected: SPIRE was not active yet, NTP was not synchronized, and the persisted
probe output lacked a completed invocation from the new boot. The later pass
did not reuse that stale output. Both the early and passing evidence digests
are retained in the sanitized receipt; raw captures and public enrollment
bodies remain private.

This was a short online warm reboot, with no power removal or offline-time
exercise. It does not qualify cold boot, hardware key isolation, rollback
protection, autonomous offline operation, fleet admission, or public DNS.
The observer uses target self-report over authenticated SSH; it does not
independently attest the physical boot chain. The original installation
observation remains unchanged.
