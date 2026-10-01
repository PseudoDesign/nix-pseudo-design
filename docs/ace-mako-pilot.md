# Ace server and Mako member pilot

The selected target uses `pilot.kaiba.pseudo.design` on the LAN. It assigns Ace the
complete pilot authority, SPIRE Server and Agent, workload registry, DNS update
services and writable DNS origin. It assigns Mako a SPIRE Agent, an exact-unit
identity probe and a read-only DNS replica. Malak now serves as the operator
workstation: complete authority state has moved, its source is fenced, and the
bounded attended workstation-power-off check has passed.

The current candidate selects merged Fleet `424d147dba78fe2ff3eabf58dda98d9928824a5c`
and DNS `e1f18fbc355b70b2d87245288d4ebb837434cbdd`. Ace's observation reader uses
Fleet's explicit `authorities-lan` package, backed by merged provisioning
`5f40fbbf4dae1d9328ad440addfd65143e3ebd18`. Historical fixture inputs, Raspberry Pi
hardware inputs and regular service inputs remain pinned. This is a candidate
source update, not an installation receipt: Ace generation 14 and Mako generation
15 remain the recorded running deployment. The thirty-day delegation and
unattended renewal are not active. Follow the
[LAN closeout gates](https://github.com/PseudoDesign/kaiba-infra/blob/codex/spiffe-spire-next-steps/docs/lan-closeout.md)
before activation; `full_qualification` remains false.

The profiles default to disabled. On September 29, both hosts passed native
builds and temporary test activation with `enable = true`, `activate = false`.
That dormant staging preserved both persistent boot baselines. Mako's same-key
credential recovery subsequently passed on September 29 local time, preserving
its identity, key and history with credential revision 2 and one successor.
Installed-key proof, fresh-process access and access after authority restart
passed. The source inventory was refreshed, Ace's original prepared keys were
retained, and policy continuity and transport signing passed without extending
the deadline. The earlier transport-signing command remains superseded.

On September 30 local time, Malak's fenced encrypted export succeeded. Import on
Ace verified complete content, schema and sequence equivalence for both
databases, and finalization passed. Ace then passed temporary activation on the
same boot, preserving its persistent baseline and existing Hydra, regular
PostgreSQL and SSH processes. Its promoted SPIRE services, imported authorities,
workload registry, DNS controller, primary and publisher are active. Four Ace
workload registrations bind exact units and users with the original deadline.
Authenticated native Reader resolution passed for both retained devices, and
independent active-binding checks matched device state. Malak's fences remain
loaded and match the sealed archive.

Both native device endpoint transfers to Ace are accepted. Fresh installed Go
client access passed with the exact retained bindings and false full-qualification
status; private backup comparison confirmed only `config.fleet_url` changed.
The explicit DNS workload grant is accepted with authenticated active-binding
readback. Ace's updater is healthy, and its assigned address record is
authoritative on both hosts. Twelve native UDP/TCP queries matched, including
matching serials; unsigned AXFR was explicitly rejected. Desired, origin and
observed publication generations agree.

Mako's temporary active profile and SPIRE admission passed. At
`2026-09-30T05:17:27Z`, acceptance confirmed the same node and key after Agent
restart with its consumed grant removed. Exact-unit probes succeeded before and
after a same-user wrong-unit request timed out after 5.057 seconds with no
identity; this was not an explicit denial response. Existing applications,
operational device state, the current candidate, persistent baseline and source
fences were preserved, and the probe timer resumed. The native positive path and
member restart passed. Remaining acceptance covers broader lifecycle/outage
checks and hardware qualification. The later warm-reboot observations below
cover startup from the installed profiles. The
earlier bounded same-host DNS trial remains expired.
The [sanitized native observation](observations/2026-09-30-ace-mako-lan-acceptance.json)
records these results and their remaining limits.

The subsequent native workload-grant check passed: active revision 1 became
quarantined revision 2, then returned to active revision 3 on the same binding.
A fresh request from the actual updater received HTTP 403 during quarantine;
the complete intent tuple, including lease and `updated_at`, stayed unchanged.
Restoration allowed a fresh accepted lease. Both authoritative DNS endpoints,
Malak's source fence and original applications were preserved. This is
fresh-request enforcement evidence, not a reused-TLS-connection check.
The [additive grant observation](observations/2026-09-30-native-workload-quarantine.json)
records this later gate without changing the initial acceptance receipt.

Two [bounded native service-outage checks](observations/2026-09-30-native-service-outages.json)
then passed. The existing registry process was paused and resumed: a fresh actual
updater request received HTTP 503 `authorization_unavailable` while all nine
intent fields stayed unchanged, then authenticated registry access and a newer
accepted lease succeeded after resume. Separately, only `kaiba-lan-primary` was
stopped; Mako retained authoritative A/AAAA/SOA answers over UDP/TCP. Primary
restart restored matching endpoints and converged controller intent. Both check
units ended inactive with successful status; grant revision 3, source fencing,
original applications and profiles were preserved. This does not cover
SPIRE/database outages, replica restart while the primary is absent, or timed
catch-up from new publication.

The later [retained-replica restart](observations/2026-09-30-native-replica-restart.json)
passed at `2026-09-30T06:42:28Z`: Mako started a new replica process while Ace's
primary was stopped, then served the same authoritative A/AAAA/SOA answers over
UDP/TCP. Independent restoration guards were armed on both hosts before the
service changes. Fresh primary-stopped observations bracketed the queries and
agreed with the primary's local absence samples. Both supervisors completed
successfully, services recovered, and credentials, device state, applications,
profiles and active revision-3 grant were preserved. This covers retained state
through a brief restart, not timed catch-up from a new publication.

[Passive identity observations](observations/2026-09-30-native-identity-observations.json)
confirmed Mako's node identity renewed beyond its earlier certificate expiry,
with its current cached trust bundle. Its existing exact-unit probe obtained a
different current workload certificate after the earlier certificate expired.
Ace's fresh exact-unit fetch passed, but rotation was not observed during that
sampling interval. No service was restarted for these observations; Fleet device
credentials/state remained unchanged. Same-process workload rotation and Fleet
operational-credential renewal remain separate checks.

The pilot policy and temporary workload registrations retain the original
deadline, `2026-10-03T02:06:35Z`. No extension is authorized or implemented.
After temporary activation and encrypted boot rehearsals, both tested profiles
were installed persistently. The owner then confirmed physical recovery access,
and both controlled warm reboots passed: Ace then ran generation 12 and Mako
generation 15. Ace includes the upstream clock waiter before storage validation,
private PostgreSQL, import validation and authority startup. Post-boot checks
included fresh exact-unit probes and preserved admitted identities, device state
and existing applications. Mako's
retained DNS answers passed in nine Ace-unavailable-bracketed query rounds during
Ace's reboot. The [persistence record](ace-mako-persistence.md) links the dated
installation and later startup evidence. The later attended workstation
power-off also passed within its recorded bounds; neither check establishes
hardware/offline qualification. Ace now runs generation 13 with the corrected
early-mount preflight. Its [repeat clean PoE cold-start](observations/2026-09-30-ace-clean-cold-start.json)
passed automatic startup, identity/state and DNS checks; all 73 Mako DNS samples
passed, including 55 during Ace unavailability. The tmpfiles missing-group
warning was subsequently fixed in active/persistent Ace generation 14 without
restarting applications. Generation 13 remains the cold-start-tested profile;
Mako remains on generation 15.

## Install, then activate

`kaiba.pilotServer.enable` and `kaiba.pilotAgent.enable` default to `false`.
Enabling a profile stages its packages, service accounts, units and narrow LAN
firewall rules. Its separate `activate` option also defaults to `false`: staged
units have no boot activation, Mako's probe timer is dormant, and Ace retains
its existing standalone SPIRE role. Staged Ace always selects an immutable
denying policy guard, even if a future guard path is configured.

Activation is a separate reviewed configuration after import and admission:

```nix
# Ace, only after the fenced import and target policy review:
kaiba.pilotServer = {
  enable = true;
  activate = true;
  policyGuard = "/nix/store/REVIEWED-TARGET-POLICY-GUARD";
};

# Mako, after an approved admission grant and private bootstrap provisioning:
kaiba.pilotAgent = { enable = true; activate = true; };
```

The placeholder is not an executable deployment configuration. Ace's import
guard verifies actual restored state, synchronized time and the original serving
deadline before starting authorities. It never initializes a new issuer or
database. The expired `kaiba.lanQualification` profile and the new server profile
are mutually exclusive. Workload grants are explicit operator operations;
enabling either profile does not create them.

## Runtime boundary

| Service | Host and listener | Access |
| --- | --- | --- |
| SPIRE Server | Ace `192.168.8.214:8081` after activation | Mako agent; existing local identity preserved |
| Observation, admission, operational issuer | Ace loopback `18441`, `18442`, `18443` | Existing authenticated authority protocol |
| Fleet lifecycle | Ace `192.168.8.214:18444` | Authenticated clients, restricted to Mako and Malak plus local use |
| Pilot PostgreSQL | Ace private Unix socket, port `18445` | Named peer users; separate from Hydra's PostgreSQL |
| Workload registry | Ace loopback `18446` | SPIFFE and current admitted membership |
| DNS update controller | Ace loopback `18447` | SPIFFE workload authorization |
| Writable DNS origin | Ace `192.168.8.214:15352` | Source-restricted queries; signed loopback updates; signed partner transfers |
| Read-only DNS replica | Mako `192.168.8.247:15353` | Source-restricted queries; transfer credential only; no update or authority key |

No public DNS delegation or router resolver change is part of this LAN profile.
Two machines on one LAN do not establish independent public DNS availability.
The publisher checks Ace and Mako as distinct endpoints.

## Required private state and cutover

1. Review the protected read-only inventory on Malak. Check source TLS SANs
   against Ace's Fleet endpoint, exact database/role names, complete authority
   history, pending signing intents, and retained policy and credential deadlines.
2. Preserve issuer scope semantics. Reader configuration includes file paths and
   endpoint values in its scope digest; moving a file or changing a Reader URL
   may invalidate the retained signing scope. Prove source/target equivalence
   before cutover. Do not rewrite the retained scope rows to make checks pass.
3. Follow the [Fleet migration contract](https://github.com/PseudoDesign/kaiba-fleet/blob/codex/spiffe-pilot-admission/deploy/pilot-migration/README.md):
   fence the source writers persistently, take consistent logical PG18 dumps and
   authority files, transfer privately, and restore into isolated target state.
   Preserve enrollment IDs, issuer history and trust. Map filesystem ownership
   by service account name; source numeric UIDs are not target assignments.
4. The target `/srv/kaiba-pilot` must already exist as root:root mode `0711`
   on Ace's existing encrypted root. Traversal allows services to reach their
   exact private subdirectories without listing the parent. Role directories
   stay mode `0700`; the import receipt is root:root `0600`, a regular single-link
   file. The profile adds a `nosuid,nodev,noexec` bind mount; it does not reformat
   storage or create imported authority state.
5. Install the separately reviewed target policy verifier and receipt without
   extending the source policy window. Imported authority configuration and keys
   remain under private runtime storage. The workload registry uses
   `/srv/kaiba-pilot/workload/config.json` and `registry.env`, plus credentials
   loaded privately from the imported Fleet directory. No private key or live
   database belongs in Git, a Nix derivation, chat or a public build output.
6. Before issuing a SPIRE bootstrap grant, confirm Mako's current Fleet admission
   and validate Agent traversal through `/var/lib/kaiba` and
   `/var/lib/kaiba/identity`. Explicitly set these shared root-owned parents to
   `0755`: `mkdir(mode=0755)` alone becomes `0700` under umask `0077`.
   Keep `member-bootstrap` root-owned `0700` and the Agent's private local state
   `0700`, owned by its service account. Missing traversal must stop preparation
   before any grant. If a grant has already expired, reconcile its use and actual
   node/state evidence before considering one explicit successor grant; do not
   automatically retry admission.
   Provision its trusted bundle at
   `/var/lib/kaiba/identity/member-bootstrap/trust-bundle.pem`, a one-time grant
   at `/run/kaiba-member-admission/join-token`, and only the DNS transfer secret at
   `/var/lib/kaiba/identity/member-bootstrap/dns-transfer.secret`. Register the
   exact service UID and unit selector for `kaiba-member-identity-probe.service`.
   Verify the actual attestation after first Agent startup. The Agent uses
   `rebootstrap_mode = "never"`; retain its consumed identity state.
7. Register Ace's registry, controller, updater and operator identities with
   their exact local unit/UID selectors and current admitted instance. An
   explicit workload request is supplied privately through
   `/run/kaiba-pilot-operator/request.json` and invoked once through
   `kaiba-pilot-operator.service`. Ambiguous outcomes require readback of that
   request, not an automatic retry with a fresh ID.

Source fencing is owner-attested software state. It does not prove hardware
anti-rollback or prevent a privileged owner starting a second writer. Once the
destination accepts writes, returning to an old source snapshot requires a new
state transfer and reconciliation.

## Validation and remaining qualification

`nix build .#checks.x86_64-linux.pilot-two-host` checks disabled, staged and
active compositions; rejected missing policy and conflicting trial profiles;
identity preservation; private listeners; distinct issuer/controller ports;
guard dependencies; and unchanged existing application units, kernel, initrd
and filesystem definitions. Disabled host closures match the retained persistent
Ace and Mako baselines. This check provides evaluation evidence.
The [composition receipt](observations/2026-09-29-ace-mako-composition.json)
records the final published dependency revisions and unchanged baseline paths.

The host's Fleet runtime pin remains `0bd55c5`, including encrypted export/restore,
restricted registry finalization and an issuer-only callback dial override that
preserves canonical URLs, TLS identity and all retained scope pins. That revision
passed 76 migration checks with real encryption and disposable PG18 clusters.
The separately reviewed migration helpers now pass **135 tests with zero skips**,
including recovered-policy continuity and exact membership/issuer-scope checks
before fencing. These helper updates do not repin the host runtime. The
host composition check also passes against this pin and both disabled closures
still match the persistent baselines. Independent staging evaluation found no
existing unit that starts a new pilot unit, unchanged application/SPIRE units
and unchanged existing user/group assignments. Expected staging effects include
new accounts, firewall/DBus reloads and Ace's empty controller SQLite placeholder;
there is no authority database initialization.
The [migration preparation receipt](observations/2026-09-29-migration-preparation.json)
records this pin and the recovery prerequisite as observed before Mako's
subsequently completed recovery.

Native dormant staging then passed on Mako at `2026-09-29T19:31:24Z` and Ace at
`2026-09-29T19:31:54Z`, using native builds of the reviewed candidates and
`switch-to-configuration test`. The
[sanitized staging observation](observations/2026-09-29-ace-mako-dormant-staging.json)
records both system paths. Selected existing application processes, Ace's SPIRE
processes, device state and directory, device ownership, boot identity and
persistent system profiles were preserved. All new pilot units were nonrunning
with no main process, and imported authority state was absent. This does not
mean every service and mount was unchanged: both activations reloaded DBus and
the firewall; Ace also restarted tmpfiles setup and started
`boot-firmware.automount`, `boot.mount`, `local-fs.target` and
`systemd-timedated`. That dormant staging did not export source state, import
target state or activate authorities; the later migration and temporary active
profile are recorded above.

The DNS dependency has a passing two-host VM covering real AXFR/NOTIFY, updates,
credential/source separation, outages, journal recovery and missing imported
credentials. The Fleet dependency passed its eight-group imported-authority VM,
including authenticated memberships, restart, and policy withdrawal/expiry with
synthetic state. These software checks are separate from the native verified
export/import. Ace's immutable target policy guard and import guard passed on
the restored state before its imported authority services started.

Remaining native acceptance covers membership revocation and instance replacement,
renewal with preserved issuer/scope/history, SPIRE/database outages,
timed catch-up from new publication and longer unattended operation. The completed
positive path, exact-unit probe, bounded wrong-unit observation, member restart
and replica queries do not
substitute for these checks; neither does the completed workload-grant quarantine
and restoration. Mako's added Agent and replica each have
`MemoryHigh = 128M`, `MemoryMax = 256M` and `TasksMax = 128`. The native sample
reported approximately 753.5 MiB available, 17.4 MB for the Agent and 13.3 MB for
the replica, with no OOM events and existing applications preserved. Longer
duration, remaining outage scenarios and load observations remain outstanding.

Within the unchanged `2026-10-03T02:06:35Z` deadline, complete the remaining native
acceptance checks. Persistent profile installation and controlled warm reboot
passed for both hosts, followed by bounded attended workstation-power-off
acceptance.
Public authority/delegation and outside-LAN DNS checks remain separate from this
LAN profile. Cold/offline boot, clock policy and hardware
rollback/recovery qualification remain separate work. Existing boot, firmware,
OTP/TPM, encrypted storage layout, Hydra, PostgreSQL, human identity, SSH CA and
backup services must retain their reviewed behavior.

The owner has confirmed physical recovery access at all three hosts. Both
independent samplers passed the read-only
[connected rehearsal](observations/2026-09-30-connected-collector-rehearsal.json), with Malak connected
and no updater timer armed. OOM observations use Ace's unchanged kernel-global
counter and Mako's unchanged per-cgroup counters; Ace has no per-cgroup memory
controller. The later [attended power-off observation](observations/2026-09-30-attended-workstation-poweroff.json)
records the owner-reported 16:45–18:00Z interval and network return about two
minutes after power-on. Fresh exact-unit identities, installed-device access and
DNS passed beyond the longest workload TTL. One separately supervised updater
restart produced a fresh lease, without claiming ordinary six-hour renewal or
same-process certificate rotation. Malak returned on a new boot; separate
verification checked retained source fences, absent listeners and unset PID1
execution metadata. Root journal visibility was unavailable, so empty journals
were not used as proof. The Pis remained powered, and full qualification remains
false.
