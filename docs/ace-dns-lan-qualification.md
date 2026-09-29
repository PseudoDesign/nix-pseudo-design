# Ace LAN DNS qualification preparation

The owner selected LAN qualification first, retaining
`pilot.kaiba.pseudo.design`. The [persistent identity pilot](ace-identity-pilot.md)
has passed a controlled online warm reboot. This composition remains disabled
by default in the source configuration. The temporary native trial is closed:
Ace is restored to generation 10 as its active, persistent and booted system.
Public delegation, router resolver configuration and existing applications
remain outside this LAN step.

`hosts/ace/dns-lan-qualification.nix` imports the dedicated DNS qualification
profile. Enabling `kaiba.lanQualification.enable` promotes the existing SPIRE
authority to a LAN listener and adds an updater, controller, publisher, primary
DNS process and two read-only replica processes. It retains the existing trust
domain, CA, agent state and identity probe. Evaluation with this option disabled
reproduces the installed generation 10 system; enabled evaluation preserves the
kernel and initrd. Mako's evaluated system is unchanged.

| Component | Planned listener or relationship |
| --- | --- |
| Existing Ace SPIRE authority | `192.168.8.214:8081`, restricted to station `192.168.8.249` plus local access |
| Station workload registry | `https://192.168.8.249:18446`, accessed by Ace with exact SPIFFE peer identity |
| Ace updater → controller | `https://127.0.0.1:18443`, mutual SPIFFE authentication |
| Writable primary | Loopback port `15352`, authenticated publisher updates only |
| Read-only replicas | Separate processes/state on ports `15353` and `15354`; LAN queries restricted to the station |
| Zone | `pilot.kaiba.pseudo.design`, queried directly; no parent delegation |

Only this explicit LAN profile permits private address updates. The updater
publishes Ace's selected `192.168.8.214` address. The normal production address
policy remains unchanged. Two replica processes on one host exercise transfer,
access control and process failures; they do not establish independent failure
domains, public reachability or DNS redundancy.

## Native candidate build

On 2026-09-29 the enabled candidate built natively on Ace with one build job and
two cores, without activation:

```text
/nix/store/ipk6rwq7h1rk4zpxyyym9s550f5i0ka7-nixos-system-ace-26.05.20260807.ee48b14
```

The [sanitized comparison](observations/2026-09-29-ace-lan-candidate-build.json)
records unchanged kernel/initrd/modules, fstab/crypttab, existing
Hydra/PostgreSQL/SSH/enrollment service and mount definitions, enrolled-state
metadata, and healthy services. Active, persistent and booted systems remained
at generation 10; no LAN service was activated.

This build used local source overrides at Fleet
`66ee0d6aa6fa3747ad69566567f465af32c31580` and DNS
`2edf05378b3b2c88773dc95044408a50a20229fc`. Both sources are now published in
[Fleet PR 30](https://github.com/PseudoDesign/kaiba-fleet/pull/30) and
[DNS PR 4](https://github.com/pd-codex/nixos-kaiba-network/pull/4). The final
remote dependency lock evaluates to the same candidate closure; disabled Ace
and Mako closures are also unchanged. This receipt establishes
a native build and preservation checks, not the enrolled-device LAN path.

## Native checks before station admission

The [sanitized native receipt](observations/2026-09-29-ace-lan-pre-station.json)
records the enabled `ipk6rwq7…` candidate test-active on Ace, with the persistent
and booted system still `ylpbjk8j…` (generation 10). At
**2026-09-29T08:22:35.667309Z**, all 15 expected services/timer were active,
including the original Hydra/PostgreSQL/SSH services and new DNS services.
The original SPIRE manifest, agent alias, valid probe identity, authenticated
public bundle and enrolled pilot status were preserved. SPIRE listened exactly
on `192.168.8.214:8081`, and all four workload registrations matched their
reviewed user-plus-unit selectors and expiry `2026-09-29T08:52:37Z`.

At **2026-09-29T08:22:24.977239Z**, an unregistered unit running under the same
Unix user was denied a workload identity; its fetch reached the deadline and
the transient failed unit was cleared. At **2026-09-29T08:23:23.780183Z**, the
controller's exact SPIFFE identity was verified and the unavailable station
registry produced HTTP **503**. The real updater was restored afterward.
These are native selector and dependency-failure checks.

Station admission was still absent. The desired-state table was empty and
queries to the primary and both replica ports returned no A or AAAA record for
`pi-001.pilot.kaiba.pseudo.design`. This receipt establishes pre-station checks;
it does not establish a successful admitted-device update, a DNS publication,
or end-to-end LAN qualification. No station apply receipt was received before
the window closed, and no persistent LAN activation is claimed.

## Closed trial and baseline restoration

At **2026-09-29T14:23:30.962325Z**, observation confirmed the scheduled stop
completed successfully and all seven new DNS units were inactive. The timer
intentionally retained the SPIRE authority; its LAN listener was still present.
The [sanitized restoration receipt](observations/2026-09-29-ace-lan-restoration.json)
then records successful guarded restoration at
**2026-09-29T14:26:10.629592Z**: active, persistent and booted systems all match
`ylpbjk8j…` (generation 10). The original manifest, valid identity probe,
public enrollment and existing services were preserved, with no unexpected
failed units. SPIRE listens only on `127.0.0.1:8081`; DNS/controller listeners
are absent.

The expired station command must not be applied. No Malak apply receipt or
successful end-to-end update was established. A future Ace/Mako topology and
any renewed authority/registration window require their own reviewed plan;
this closed trial does not deploy new services on either Mako or Malak.

## Current-admission and station prerequisites

The existing pilot inventory and authenticated admission/observation services
stay on Malak. The station bridge needs a dedicated SPIRE agent joined to Ace,
a registry using `inventory_mode = "pilot"` with the exact pinned current policy,
and an operator identity separate from the DNS controller. It must not copy
membership into the older `enrollments` table or broaden the existing pilot
credential's permissions.

A read-only owner-run station preflight on 2026-09-29 confirmed the actual
current Ace tuple and reader configuration. The active enrollment identifies logical device
`pilot-834bb1682a637bfa3522d524314864961ed9a82e86d5a25d` and instance
`857bfe871759fd73c32f565ab5db97412fd049af9941eab4`. These are different from the
identity probe's `ace/ace-pilot-20260929` labels. Proposed numeric assignment
`001` belongs only to this isolated LAN zone and still requires an explicit
operator grant and readback; it is not an existing DNS permission.

The registry must use the current `public.pilot_enrollments` table, with
SELECT/REFERENCES permissions and a separate owned workload schema. Qualifying
the inventory schema prevents an identically named table in that workload
schema from substituting for real membership. Parent inventory updates must be
denied by PostgreSQL. Existing authorities and their encrypted storage/serving
window remain authoritative. Station credentials stay local and runtime-only.

The workspace lacks passwordless root access to Malak. The initial read-only
preflight and reviewed service preparation were completed for the now-expired
window. No station application receipt was received. Any resumed work needs
a fresh reviewed plan and deadline. Preparation exposes no keys or database
credentials.

## Activation and acceptance sequence

1. Build and review the pinned host candidate, station bridge and public
   registration/grant plan. Recheck current admission and serving deadlines.
2. Retain Ace's current generation 10 and compare its kernel, initrd, mounts,
   existing service units and public enrolled-device state. Use the guarded
   boot-automount activation procedure from the identity pilot.
3. Register exact user-plus-systemd-unit controller and updater identities
   under the existing Ace node. Enroll the station agent through a short-lived
   consumed grant and pinned existing bundle; register its registry/operator
   identities narrowly. Never put a grant or private key in a Nix expression.
4. Start the isolated services and verify current membership without a DNS
   grant is denied. Issue the reviewed numeric assignment via the operator API,
   read it back, and run the updater. Query both replica ports directly.
5. Verify wrong-workload denial, grant quarantine/removal and authority or
   database outage denial without stale allowance; retain the same assignment
   across valid credential rotation. Test replica stop/recovery and restart
   persistence. Keep existing Hydra/PostgreSQL/enrollment health in the report.
6. Make the reviewed generation persistent only after native acceptance.
   Preserve existing authority and enrollment state during software recovery.

The original activation helper is tied to the earlier generation-9 baseline;
review it for a generation-10-to-LAN transition rather than replaying its old
arguments. No native LAN result is claimed by a successful evaluation or VM
check. Cold boot, offline time and authority-state rollback qualification remain
separate physical evidence requirements.
