# Ace server and Mako member pilot

The selected target uses `pilot.kaiba.pseudo.design` on the LAN. Ace hosts the
complete pilot authority, SPIRE Server and Agent, workload registry, DNS update
services and writable DNS origin. Mako hosts a SPIRE Agent, an exact-unit identity
probe and a read-only DNS replica. Malak becomes an operator workstation after
the complete authority state has moved and normal operation has passed with
Malak disconnected.

These profiles are implemented but disabled. No authority migration, Mako agent
admission or native two-host acceptance has occurred. Malak still holds the live
pilot control plane. The earlier bounded same-host DNS trial has expired and
Ace's persistent standalone identity baseline is restored.

The reviewed September 29 inventory confirms the complete source authority.
Ace's transfer recipient and transport CSR were prepared on encrypted storage;
its private keys stayed on Ace. Native preflight authenticated Ace, but Mako's
installed credential expired at `2026-09-28T08:03:32Z`. Its local `verified` phase
does not establish current admission. Supported same-key recovery must preserve
Mako's logical identity, instance, key and history before two-host qualification.
That recovery needs exact Fleet/issuer grants and a new serving-policy baseline,
followed by fresh migration inventory and transport/target-policy bindings. The
earlier transport-signing command is superseded; Malak remains serving while the
read-only recovery preflight is reviewed.

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
6. Confirm Mako's current Fleet admission and approve its SPIRE bootstrap grant.
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
and filesystem definitions. Disabled host closures match the existing installed
Ace and Mako baselines. This is evaluation evidence, not a native deployment.
The [composition receipt](observations/2026-09-29-ace-mako-composition.json)
records the final published dependency revisions and unchanged baseline paths.

The current Fleet runtime pin is `0bd55c5`, including encrypted export/restore,
restricted registry finalization and an issuer-only callback dial override that
preserves canonical URLs, TLS identity and all retained scope pins. Its 76
migration checks pass with real encryption and disposable PG18 clusters. The
host composition check also passes against this pin and both disabled closures
still match the installed baselines. Independent staging evaluation found no
existing unit that starts a new pilot unit, unchanged application/SPIRE units
and unchanged existing user/group assignments. Expected staging effects include
new accounts, firewall/DBus reloads and Ace's empty controller SQLite placeholder;
there is no authority database initialization.
The [migration preparation receipt](observations/2026-09-29-migration-preparation.json)
records this pin and Mako's observed recovery prerequisite.

The DNS dependency has a passing two-host VM covering real AXFR/NOTIFY, updates,
credential/source separation, outages, journal recovery and missing imported
credentials. The Fleet dependency passed its eight-group imported-authority VM,
including authenticated memberships, restart, and policy withdrawal/expiry with
synthetic state. These checks do not establish source
export consistency or native migration.

Native acceptance still requires authenticated current admission and denial,
renewal with preserved issuer/scope/history, exact workload identity and wrong-unit
denial, real update publication and queries on Mako, service restart, and normal
operation while Malak is disconnected. Mako's added Agent and replica each have
`MemoryHigh = 128M`, `MemoryMax = 256M` and `TasksMax = 128`; verify headroom while
its existing applications remain healthy.

After a successful bounded test activation, verify persistent configuration and
controlled warm reboot separately. Cold/offline boot, clock policy and hardware
rollback/recovery qualification remain separate work. Existing boot, firmware,
OTP/TPM, encrypted storage layout, Hydra, PostgreSQL, human identity, SSH CA and
backup services must retain their reviewed behavior.
