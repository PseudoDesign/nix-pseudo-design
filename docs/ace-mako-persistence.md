# Persistent Ace/Mako pilot profiles

Both controlled warm reboots passed on September 30 after the owner confirmed
physical recovery access. Ace then ran persistent generation 12 with an explicit
clock waiter and ordered authority startup; Mako runs guarded generation 15.
Post-boot checks preserve admitted identities, device state and existing
applications. DNS remained available in bounded Mako samples during Ace's reboot.
The later attended workstation-power-off check also passed within its recorded
bounds; hardware qualification remains false. The dated rehearsal and boot-only
installation records below are
preserved separately from the later startup observations.

The subsequent [clean PoE cold-start test](observations/2026-09-30-ace-cold-start-ordering-failure.json)
failed automatic-startup acceptance on Ace generation 12. A mount-preflight
ordering cycle caused PID1 to discard startup jobs. Identity and authority state
survived, and affected services were restored explicitly. The fix is now installed
as generation 13. The [repeat clean PoE test](observations/2026-09-30-ace-clean-cold-start.json)
passed automatic startup, retained identity/state and DNS without manual service
starts. Mako passed all 73 DNS samples, including 55 while Ace was unavailable.
The later [tmpfiles cleanup](observations/2026-09-30-ace-tmpfiles-cleanup.json) is installed and active
as generation 14. It preserves root-only debugfs permissions and all application
processes. Ace has not rebooted again: generation 13 remains the cold-start-tested
profile, and Mako's profile has not changed.

## Initial tested baseline and declarative selection

The [explicit profile constructor](../deploy/pilot-profiles.nix) keeps the normal
host configurations disabled and requires the reviewed guard with Nix reference
context. That context keeps the guard, verifier sources, configuration and Python
closure reachable when the selected system is retained by a system profile.

```nix
import ./deploy/pilot-profiles.nix {
  hosts = hostFlake.nixosConfigurations;
  policyGuard = reviewedGuardDerivation;
  guardAdmittedMember = true;
}
```

The returned `systems.ace` and `systems.mako` are build targets; `configurations`
contains their complete evaluated configurations. This does not create or copy
private admission state. Supply the exact already reviewed policy guard; do not
replace it with a path-only string or a new permissive script.

With `guardAdmittedMember = false`, evaluation reproduced both native-tested
closures exactly:

| Host | Temporary active closure | Persistent generation before this change |
| --- | --- | --- |
| Ace | `/nix/store/jqhncbfidhni7896ds8y74m4k8qnikc5-nixos-system-ace-26.05.20260807.ee48b14` | 10: `/nix/store/ylpbjk8jzr195l7yn7f713sgjfimicbs-nixos-system-ace-26.05.20260807.ee48b14` |
| Mako | `/nix/store/w3fpk6jc50xmwy76b48ycjhfj6b4iira-nixos-system-mako-26.05.20260807.ee48b14` | 14: `/nix/store/nf6pj4bqp2gp4j9rf4d23bfgsh6lcbjf-nixos-system-mako-26.05.20260807.ee48b14` |

Before the initial persistent installations, Ace had booted generation10 and
Mako generation13, whose closure is
`/nix/store/f0k23wljli44yqrf4mz6n530w9af5k6k-nixos-system-mako-26.05.20260807.ee48b14`.
Read-only native comparison found identical kernel, initrd, DTB, kernel-module
and firmware targets between each tested candidate, persistent baseline and
actually booted closure. Existing application units and filesystem definitions
also remain equal in the profile evaluation check.

The admitted-state guard below deliberately changes Mako's service definition.
The guarded candidate is **not** the previously tested `w3f…` closure. It required
a separate native build, review and temporary activation before persistence.
The false setting is retained for explicit bootstrap and historical comparison;
it is not the selected admitted persistence mode.

The corrected guarded candidate
`/nix/store/k5xi0bjwxfqm4nzgpm43k8ijam1n2j9w-nixos-system-mako-26.05.20260807.ee48b14`
built natively and passed temporary activation at `2026-09-30T07:07:29Z`.
The [native startup observation](observations/2026-09-30-mako-startup-guard.json)
records successful pre-start validation, Workload API readiness, a new Agent
invocation, a fresh exact-unit identity probe and authenticated installed-client
access. The same admitted node, original admission receipt, device state,
applications and running DNS replica were preserved. Its persistent selection
was unchanged by that test.

## Already-admitted Mako startup

`kaiba.pilotAgent.admittedState.enable` defaults to false, preserving the explicit
initial admission workflow. The persistence profile explicitly sets it true.
Before SPIRE starts, a root read-only guard requires:

- an existing root-private `member-bootstrap/admitted-startup.json` receipt matching host,
  trust domain, server address/port, local state directory and original deadline;
- the receipt's digest of the previously verified node URI, without publishing
  that internal URI in Nix, logs or documentation;
- an intact current cached node certificate, a matching public key in one of the
  existing A/B disk slots, and a valid chain to the current cached trust bundle;
- expected private ownership/modes, no symlink state, no remaining join grant,
  and synchronized time.

The receipt does not pin a leaf serial, a key-file digest or a single CA. Normal
node/key and CA rotation must remain accepted under the same admitted identity.
An operator creates the receipt once from independently verified admission and
current private state; activation never creates it. Missing, expired or
mismatched state fails before the SPIRE process can generate or replace a key.
The guard does not recover state, extend admission, issue a grant or edit files.
Its parser is explicitly tied to SPIRE1.15.2; an upgrade needs a format review.
The historical `member-bootstrap/admitted.json` remains a separate, unchanged
admission record. Startup uses `admitted-startup.json`; a missing startup receipt
does not fall back to or replace the historical one. Native preparation verified
the historical authority-confirmed node before creating the new receipt.

The cached node leaf must have **more than 120 seconds** remaining at validation.
Systemd bounds each pre-start and readiness phase to 90 seconds. The guard
checks validity after its clock wait; the subsequent health probe keeps the
service in startup while SPIRE opens the Workload API socket. That socket becomes
available after SPIRE loads the node identity and initializes its manager. If
readiness is not reached within its 90-second phase, systemd kills the starting
control group; an ordinary simple-service fork alone is not readiness.
This provides bounded checking with synchronized time, not protection against
arbitrary clock jumps or indefinite suspension. A certificate too close to
expiry requires an independently reviewed recovery instead of implicit key
replacement. Normal online node rotation remains accepted.

This guard addresses a concrete behavior in that version: `rebootstrap_mode =
"never"` does not prevent initial key generation when a cached node SVID cannot
be reused. An expired cache can write the alternate A/B slot; missing/unmatched
cache can overwrite slot A before token attestation fails. Network denial alone
therefore does not guarantee unchanged disk keys.

The configured bootstrap PEM is not the normal restart trust source when a valid
cache exists. SPIRE first loads the cached bundle from `agent-data.json` and
persists online bundle rotation atomically. Preserve the entire cache and disk
key directory. No custom periodic bootstrap-file refresh is needed for that
normal path. Missing cached trust still fails this admitted guard.

## Boot guards and deadlines

Ace's authority startup requires the existing encrypted import, private receipt,
static-file and current database continuity checks, exact policy guard and
synchronized time. The authority target waits for the time synchronization
service. Its monitor checks time/policy continuously; guard failure stops the
bound authority, workload-registry and DNS primary/update services. It does not
create a replacement database or silently enable the fenced source.

Ace's separate identity bootstrap guard requires its existing manifest, keys,
node SVID and original registrations; its local admin API refreshes the persisted
bootstrap bundle before its agent starts. Missing state or an expired node SVID
requires explicit recovery. Neither host is qualified for arbitrary offline
clock conditions or power-off intervals exceeding usable cached identity.

All original policy and workload-registration expiry remains
`2026-10-03T02:06:35Z`. Installing a persistent profile does not extend it. Mako's
admitted startup guard uses that same bound. Existing processes are not all
instantaneously retired by this new pre-start check: Mako's DNS replica has its
own zone-expiry behavior, and the standalone SPIRE authority is a separate
identity service. Do not describe the deadline as a universal host shutdown.
No automatic node grant, operator workload grant or renewal is added at boot.

## Protected boot rehearsal before installation

The pinned Pi `kernel` bootloader is generational. It selects
`os_prefix=nixos/default/` in `/boot/firmware/config.txt`. Both hosts use the
same immutable builder:

```text
/nix/store/caglx0kwjli1bxzdcijbsjm3xm4s3h60-nixos-generations-builder.sh -g 4 -f /boot/firmware -c
```

It rewrites firmware/configuration first, builds each generation's kernel,
initrd, command line and DTBs in a temporary directory, publishes complete
directories, and removes obsolete generation directories. It is not one atomic
transaction covering the whole FAT volume. An older generation whose initrd
secret appender fails may be skipped and then removed from the boot directory.
Keeping a Nix profile symlink alone does not preserve usable firmware recovery
files.

Read-only inspection activated only the existing configured boot automounts.
The actual firmware FAT on each host is `/dev/nvme0n1p1`. Ace initially had about
556.5MB free and entries7–10 plus default; Mako had about514.0MB free and entries
11–14 plus default. Their encrypted roots had about141.8GB and207.3GB available.
Those are observations, not fixed deployment requirements; recheck immediately
before staging. The complete boot trees were about509.9MB and552.3MB respectively.
The nested firmware automount can be inactive after its parent idles. Reading
`/boot/firmware` then reaches a directory on the separate parent boot partition.
Activate only the existing configured automount, verify the actual `p1` device,
and hold a verified directory descriptor throughout staging and installation.
A readable `config.txt` alone is insufficient; reject the parent partition.

Ace's retained generations have no initrd-secret appenders. All retained Mako
profiles and its active candidate have appenders; their existence is not proof
that they can still materialize every older generation's required inputs.

Before any real boot write, use a fresh root0700 directory on the existing
encrypted root. Capture a private full firmware backup with complete path/type/
mode/size/hash manifest and verify readback. Then run the exact immutable builder
against a **new staging directory**, keeping the real boot volume and system
profile untouched:

```sh
# Reviewed operator variables must contain the exact candidate and a new
# root0700 operation directory on the verified encrypted root.
/nix/store/caglx0kwjli1bxzdcijbsjm3xm4s3h60-nixos-generations-builder.sh \
  -g 4 -f "$pilot_boot_operation/boot-stage" -c "$pilot_candidate"
```

Do not run this illustrative command with an unset or unverified destination.
The operation must prove sufficient staging/backup space and no symlinks; the
operator must first create the destination with private permissions. Treat
staged initrds and backup archives as private because they can contain boot
secrets. Do not copy them to the workstation, Nix store or repository.

Before a profile-link update, staging produces the new candidate as `default`
and the four currently selected older slots. Require every expected retained
slot and its usable initrd; reject skipped generations. Verify configuration,
firmware, kernel/DTB and command-line scope, plus unchanged actual FAT manifest,
current system, all profile links, boot identity and original application PIDs.
The actual installation after creating a new profile generation uses four slots
including that new numbered generation: the oldest current FAT entry7 on Ace or
11 on Mako will leave the selected set. Preserve it in the verified encrypted
backup and report this retention change explicitly. Baseline10/14 and actually
booted10/13 remain within the selected set. Do not silently increase retention
or prune Nix profile generations.

Mako completed the protected rehearsal at `2026-09-30T07:24:14Z`; the
[native observation](observations/2026-09-30-mako-boot-rehearsal.json) records a
successful supervisor completion and independent readback. A complete private
firmware backup and a fresh staged default plus all four retained entries stayed
on Mako's verified encrypted filesystem. The real firmware, profile links,
running applications, SPIRE Agent and DNS replica were unchanged. The current
admitted identity was validated with the startup guard; normal online key and
certificate rotation was allowed. The source authorities remained stopped with
their loaded migration fences.

The Mako initrd check compared each immutable prefix and the exact required
secret path, contents and mode privately, using bounded decoding of one appended
zstd/newc archive. This checks the actual material despite possible archive
timestamp differences. The appender's temporary directory also remained on the
verified encrypted filesystem. No secret material or private backup was exported.
The rehearsal installed no persistent profile or boot default and performed no
reboot. It does not establish power-loss, offline, physical recovery or hardware
qualification; the original `2026-10-03T02:06:35Z` deadline remains unchanged.

## Boot-only installation and ambiguous failure

The root coordinator must first complete the guarded Mako candidate review and
native test, valid admission receipt, current policy/node lifetime checks,
protected backup and staged boot verification. Execute one host at a time, with
exclusive durable intent recording the exact candidate, old profile link,
selected generations and boot manifest. The intended final actions are:

```sh
"$pilot_candidate/sw/bin/nix-env" --profile /nix/var/nix/profiles/system --set "$pilot_candidate"
"$pilot_candidate/bin/switch-to-configuration" boot
```

These are review instructions, not a request to rerun deployment. Use the exact
already built and tested closure, not a flake rebuild with potentially different
inputs. `boot` updates the next boot's files; do not substitute `switch`, `test`,
`reboot` or an installer. Retain the previous generation links and native GC roots.
Keep the `nix-env` executable name: it is a multi-command binary alias. Resolving
that symlink and executing `nix --profile ... --set ...` selects the wrong CLI.
Verify the immutable alias with `--version` before the recorded profile write.

A profile-link update and bootloader update are two separate operations. If the
process fails between them, the running system can remain healthy while the
profile link and selected boot files disagree. Keep the durable intent and
backup, inspect the exact link and actual default `system-link`/command line,
then choose a reviewed completion or restoration. Do not blindly rerun the
builder, remove generations or report success merely because the link changed.
If a real firmware update partially failed, restore from verified private boot
backup or complete the exact staged candidate only after reviewing the actual
volume; resetting a symlink alone does not repair the boot volume.

Final readback must show the intended persistent profile and default boot entry,
all required retained recovery entries, correct protected boot hashes, unchanged
running closure/processes and source fences, and healthy current pilot/DNS
behavior. No reboot is part of this installation. Controlled warm reboot is a
separate acceptance step, recorded below; boot installation alone does not prove
startup, physical recovery or power-loss safety.

## Recorded boot-only installation

Ace's [boot installation observation](observations/2026-09-30-ace-boot-install.json)
was independently reconciled at `2026-09-30T07:26:31Z`. Persistent generation 11
and the default boot entry selected the exact running `jqhn…` candidate.
At that point, numbered firmware entries 11, 10, 9 and 8 were available; entry 7 was retained
in the verified encrypted backup and its Nix generation link remains intact.
Actual firmware matched the encrypted stage, the booted generation stayed at
10, and existing applications and device state were preserved. Fresh LAN DNS
and Malak source-fence checks passed afterward. That installation did not test
startup; Ace's later generation-12 warm reboot is recorded separately below.

Mako's [boot installation observation](observations/2026-09-30-mako-boot-install.json)
was independently reconciled at `2026-09-30T07:36:30.208904Z`. Persistent generation 15
and default boot selected the guarded `k5xi…` candidate. Firmware entries
15, 14, 13 and 12 were retained; entry 11 remains in the verified encrypted backup and
its Nix profile link is intact. The previous persistent generation 14 and
actually booted generation 13 retain their kernel/configuration/DTB bytes and
verified equivalent initrd contents. Exact immutable prefixes and private
appended material were checked; temporary appender material was absent after
completion. Both admission receipts, source material, Agent, replica and other
application processes, and device state were preserved. Final both-host health,
UDP/TCP DNS, unsigned AXFR denial and Malak source-fence checks passed.
No reboot or workstation disconnection was part of those installation operations.

## Controlled warm reboots

With physical recovery access confirmed, Mako passed a controlled warm reboot
into its persistent generation 15. Its admitted-state guard accepted the retained
node without a join grant. Existing applications, SPIRE Agent and DNS replica
started automatically; installed device access and a fresh exact-unit probe
passed. The [Mako observation](observations/2026-09-30-mako-warm-reboot.json)
records the new boot and preserved private state.

Ace then passed a controlled warm reboot into persistent generation 12. The
[Ace observation](observations/2026-09-30-ace-warm-reboot.json) records final
acceptance at `2026-09-30T15:29:30Z`, including a fresh automatic exact-unit probe
on the new boot, current installed-device access, converged publication,
both-host DNS queries and unsigned AXFR denial. That candidate includes the
upstream `systemd-time-wait-sync.service`, which was
missing from the earlier active profile despite an existing ordering dependency.
Actual monotonic startup timestamps verify clock wait before the storage guard,
private PostgreSQL, import guard and Fleet; all four authority APIs passed their
post-boot checks. Current, persistent and booted
profiles agree; the imported authorities, registry, DNS services and original
applications started automatically. Identity, device and static private state
were preserved, and no failed units remained.

During Ace's reboot, all 34 Mako observations passed; nine complete A/AAAA/SOA
UDP/TCP query rounds had fresh Ace SSH/primary-DNS unavailability observations
before and after the queries. Mako retained the same boot, profiles and seven
service PIDs, invocation IDs and unit contents. Ace's return was observed.
This establishes sampled replica continuity during the controlled reboot, not
continuous availability at every instant or a second replica restart.

Malak remained connected during these warm reboots. The subsequent
[connected sampler rehearsal](observations/2026-09-30-connected-collector-rehearsal.json) passed with
11 complete Ace samples and 10 Mako samples, with zero failures. The longest
samples took 683.5 ms and 409.44 ms respectively; maximum sample gaps were
30.008 and 30.006 seconds. Installed-client, identity-probe, DNS and protected-state
checks passed; no updater timer was armed.
Ace's OOM evidence is the unchanged kernel-global `oom_kill` counter because its
kernel lacks the memory cgroup controller. Mako uses unchanged per-cgroup
`memory.events` counters. Neither source is silently substituted for the other.

The packet passed 68 focused software tests, including client-lock ordering and
sample/action coordination.

## Attended workstation power-off

The [additive observation](observations/2026-09-30-attended-workstation-poweroff.json)
records the later owner-reported Malak power-off from 16:45–18:00Z on September
30. Ace, Mako and the router stayed powered. Network return was observed about
two minutes after the reported power-on. Both independent samplers passed
through the interval: fresh exact-unit credentials after the longest prior TTL,
installed-device access, cross-host DNS and protected-state checks succeeded.
Each host recorded 173 samples with zero failures, including 13 installed-device
and DNS query matrices after the full TTL margin while Malak was still off.
Ace recorded 18 fresh-probe samples in that period and Mako 15; these are sample
counts, not distinct certificate counts. One separately supervised updater restart
produced a fresh accepted lease after that TTL. This was an induced update, not
ordinary six-hour periodic renewal or same-process certificate rotation.

Malak returned on a new boot. The original unchanged-boot verifier was preserved,
and a separate supplement checked the owner attestation, bounded network return
and source fencing. All six source units retained their persistent fences and
unset PID1 main-process execution metadata, with no authority listeners. Root
journal visibility was unavailable; empty unit journals were not treated as proof
of non-execution. Ace uses unchanged kernel-global OOM evidence and Mako uses
unchanged per-cgroup counters.

The Pis were not power-cycled in this check. Cold/offline boot, power-loss safety,
rollback and physical recovery qualification remain open; the original
`2026-10-03T02:06:35Z` deadline is unchanged and full qualification remains false.

## Clean PoE cold-start: ordering failure

The owner confirmed a completed console shutdown, removed Ace's sole PoE supply
for 30 seconds, and reconnected it. Ace has no RTC backup battery; networking
was available on reconnect. Exact power-transition wall times were not recorded.
The [observation](observations/2026-09-30-ace-cold-start-ordering-failure.json)
records a changed boot, accessible encrypted root, retained admitted node/device
state, synchronized-clock authority startup, and primary DNS return.

Automatic startup failed. `kaiba-pilot-import-present.service` inherited the
normal service ordering after `basic.target` and `sysinit.target`, but runs
before a mount ordered before `local-fs.target`. PID1 broke the resulting cycle
by deleting startup jobs, including `systemd-tmpfiles-setup.service`. Avahi then
failed to create its runtime directory, while the controller and publisher
remained inactive. Initial `ace.local` checks failed; direct-IP SSH used the
same pinned host key. A nonzero failed-unit count alone would also have missed
the inactive controller and publisher.

After preserving logs and protected-state evidence, explicit starts restored
tmpfiles setup, Avahi, controller and publisher. The restored snapshot passed
fresh exact-unit identity, installed-device access, DNS, profile and retained
state checks. That recovery does not turn the cold-start result into a pass.
Mako passed all 40 sampled six-query DNS matrices, including 12 bracketed by
Ace SSH and primary DNS unavailability. Its observer is stopped. Malak's six
authority services remain fenced and inactive, with no authority listeners.

The source fix disables default dependencies only for the early directory
preflight, orders it after root remount, and explicitly retains shutdown
ordering/conflict. It preserves the directory/manifest checks and mount guard.
The fix was subsequently built natively from host commit `579cca0` and installed
as generation 13. Only the early-preflight unit changed; kernel, initrd,
firmware inputs and the pinned Fleet runtime stayed unchanged. The boot writer
succeeded, but the installer could not find `sync` in its service environment.
Reconciliation verified the selected profile, full encrypted backup and expected
firmware, then completed the final sync through an immutable executable alias.
Neither the profile nor firmware writer was repeated; no Nix generation was deleted.

## Repeat clean PoE cold-start: passed

The owner again confirmed completed console shutdown and 30 seconds without
Ace's sole PoE supply, then reconnected it. No RTC backup battery is fitted;
LAN was available on return. The [dated observation](observations/2026-09-30-ace-clean-cold-start.json)
records a new boot into generation 13, accessible encrypted root, retained
node/device/admission state, fresh exact-unit identity, installed-device access
and matching DNS. All 17 protected services started automatically. The early
preflight completed before the state mount, tmpfiles and Avahi; current-boot
PID1 evidence shows no ordering cycle or deleted startup jobs and no failed units.
Clock synchronization preceded storage validation and authority startup.

An initial snapshot reached a protected service before it was running; the later
read-only snapshot passed without service starts or restarts. The early checker
was corrected to request mount-specific fields and recognize tmpfiles' declared
success exit statuses. Tmpfiles returned accepted exit 65 with a missing `sudo`
group warning from `/etc/tmpfiles.d/sys-kernel-debug.conf`; retain this separate
cleanup item rather than describing boot as warning-free. Original checker
failures and corrected verification are retained in the private evidence manifest.

Mako passed all 73 sampled UDP/TCP A/AAAA/SOA matrices, including 55 bracketed
by Ace SSH and primary DNS unavailability. The first fully connected return
sample ended about 578 seconds after the shutdown request, within the ten-minute
return budget; this does not measure the exact physical off interval. The owner
reported that interval as 30 seconds. The observer is stopped, and Malak's six
authority services remain fenced and inactive with absent listeners.

Offline time, abrupt power loss, rollback and full hardware qualification remain
open under the unchanged `2026-10-03T02:06:35Z` pilot deadline.

## Tmpfiles cleanup and remaining physical gates

The Raspberry Pi package supplied `d! /sys/kernel/debug 0750 root sudo -`,
but these NixOS hosts have no `sudo` group. The shared Pi profile now replaces
that exact file with `d! /sys/kernel/debug 0700 root root -`, preserving Ace's
observed root-only permissions without creating a group or granting debugfs
access to administrators. A real systemd-tmpfiles fixture reproduces exit 65
with the original rule and passes with the replacement.

The [cleanup observation](observations/2026-09-30-ace-tmpfiles-cleanup.json) records a native build,
verified boot-only installation as generation 14, and subsequent activation
without reboot. The rendered tmpfiles directory changes only that rule; the
only unit change is the tmpfiles resetup restart trigger. Kernel/initrd/firmware
inputs and application units are unchanged. Tmpfiles resetup and the native
boot-rule dry-run now return zero. All protected application processes and
identity/state checks are preserved, and all 12 cross-host DNS queries pass.
The cold-start result still belongs to generation 13; generation 14 is active
and selected for the next boot, while Mako remains on generation 15.

No spare storage is available for interrupted-write experiments. Abrupt power
cuts of the live authority disk are deferred until disposable media and a tested
restoration route exist. Ace's pilot requires online synchronized time and has
no RTC backup battery. The next physical test can observe refusal with
untrusted time and recovery after networking returns, once the owner confirms
independent console access and data isolation that retains PoE. It cannot
establish autonomous offline operation. See the [remaining physical-test
procedure](https://github.com/PseudoDesign/kaiba-infra/blob/codex/spiffe-spire-next-steps/docs/offline-qualification.md#current-pilot-remaining-physical-tests).

## Checks

```sh
nix build .#checks.x86_64-linux.pilot-two-host
nix build .#checks.x86_64-linux.rpi-tmpfiles
nix build .#checks.x86_64-linux.member-identity-guard
```

The composition output includes rendered units for the boot-graph regression:

```sh
composition=$(nix build .#checks.x86_64-linux.pilot-two-host --no-link --print-out-paths)
PREFLIGHT_UNIT="$composition/kaiba-pilot-import-present.service" \
PILOT_MOUNT_UNIT="$composition/pilot.mount" \
SYSTEMD_ANALYZE="$(command -v systemd-analyze)" \
python3 tests/pilot_mount_order_test.py
```

Run this read-only graph verifier on a Linux host with systemd's runtime
directory available; the Nix build sandbox lacks `/run/systemd`. It reproduces
the old cycle and startup job deletion, then verifies the corrected rendered
unit in an isolated fixture root. PID1 can return success after deleting jobs,
so the regression also checks diagnostics rather than only the exit status.

The first check includes explicit active-profile construction, refusal of a
contextless guard, preserved unrelated units/kernel/initrd/filesystems, bootstrap
versus admitted member selection and boot dependencies. The second exercises
synthetic retained identity/key/bundle rotation, malformed/expired/missing state
and read-only refusal. These checks are separate from native candidate testing
and do not provision receipts or install boot files.

## Prepared owner-term continuation (not activated)

`kaiba.pilotAgent.admittedState.continuity` defaults to `null`. An explicit
continuation requires the existing startup guard, separate root-private receipt
and reader configuration with immutable SHA-256 pins, a reviewed Fleet package
providing `kaiba-pilot-host-term`, and the exact revision-one delegation and
retained enrollment ID. Both files must stay beside the original startup receipt;
the original receipt and its deadline remain unchanged historical evidence.

At startup the reader authenticates with the enrollment's confined service
identity and checks the latest delegation and membership on Ace. Revocation,
expiry, changed identity/key/issuer/permissions, unreachable authority or a stale
response blocks startup. A retained delegation file alone cannot authorize it.
The continuation must have been approved before the original cutoff and must
end exactly thirty days after activation. The cached admitted node certificate
must remain valid through startup and cannot outlast that term. No bootstrap,
replacement identity, automatic recovery or receipt creation is performed.

This option has synthetic tests but is not enabled in the pilot profiles. It
requires Ace's compatible authority transition and coordinated SPIRE issuance
bounds before live deployment. It is not a substitute for continuous expiry and
revocation enforcement, and it does not start the twenty-four-hour observation.
