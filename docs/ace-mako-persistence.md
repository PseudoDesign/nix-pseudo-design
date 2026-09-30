# Persistent Ace/Mako pilot profiles — prepared, not installed

The September 30 LAN, workload-grant and bounded service-outage checks passed on
temporary profiles. This document prepares persistence without rebooting either
host. There is currently no physical recovery access. No boot default, profile
link, authority state or existing application is changed by the repository
configuration or its evaluation checks.

## Exact running baseline and declarative selection

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

Ace booted generation10; Mako booted generation13, whose closure is
`/nix/store/f0k23wljli44yqrf4mz6n530w9af5k6k-nixos-system-mako-26.05.20260807.ee48b14`.
Read-only native comparison found identical kernel, initrd, DTB, kernel-module
and firmware targets between each tested candidate, persistent baseline and
actually booted closure. Existing application units and filesystem definitions
also remain equal in the profile evaluation check.

The admitted-state guard below deliberately changes Mako's service definition.
The guarded candidate is **not** the previously tested `w3f…` closure. Build,
review and temporarily test that new candidate before choosing it as persistent.
The false setting is retained for explicit bootstrap and historical comparison;
it is not the selected admitted persistence mode.

## Already-admitted Mako startup

`kaiba.pilotAgent.admittedState.enable` defaults to false, preserving the explicit
initial admission workflow. The persistence profile explicitly sets it true.
Before SPIRE starts, a root read-only guard requires:

- an existing root-private `member-bootstrap/admitted.json` receipt matching host,
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

## Boot-only installation and ambiguous failure

The root coordinator must first complete the guarded Mako candidate review and
native test, valid admission receipt, current policy/node lifetime checks,
protected backup and staged boot verification. Execute one host at a time, with
exclusive durable intent recording the exact candidate, old profile link,
selected generations and boot manifest. The intended final actions are:

```sh
nix-env --profile /nix/var/nix/profiles/system --set "$pilot_candidate"
"$pilot_candidate/bin/switch-to-configuration" boot
```

These are review instructions, not a request to rerun deployment. Use the exact
already built and tested closure, not a flake rebuild with potentially different
inputs. `boot` updates the next boot's files; do not substitute `switch`, `test`,
`reboot` or an installer. Retain the previous generation links and native GC roots.

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
behavior. No reboot is part of this installation. Controlled warm-reboot and
physical recovery acceptance remain pending physical access; a successful boot
installation cannot establish them.

## Checks

```sh
nix build .#checks.x86_64-linux.pilot-two-host
nix build .#checks.x86_64-linux.member-identity-guard
```

The first check includes explicit active-profile construction, refusal of a
contextless guard, preserved unrelated units/kernel/initrd/filesystems, bootstrap
versus admitted member selection and boot dependencies. The second exercises
synthetic retained identity/key/bundle rotation, malformed/expired/missing state
and read-only refusal. These checks are separate from native candidate testing
and do not provision receipts or install boot files.
