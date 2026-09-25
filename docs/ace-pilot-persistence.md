# Ace's existing pilot credential persistence

Ace enables `services.kaibaPilotDevice` with the UID/GID already assigned to its
enrolled account. The module preserves the existing private state in
`/var/lib/kaiba-pilot-device`; it never initializes, reads, replaces or changes
ownership of a key file. Mako does not enable this module.

The declarative nonlogin account uses UID 994 and GID 988. A boot-time metadata
check requires an existing nonsymlink directory owned by that account with mode
0700, and an existing single-link regular `state.json` with mode 0600 and the
same ownership. Missing or unsafe state fails the mount dependency without
creating a new identity or repairing evidence silently.

The systemd self-bind mount supplies `rw,nosuid,nodev,noexec`. The metadata check
is ordered before the mount and can run before local filesystems finish without
a default-service dependency cycle. The deployed client still independently
checks the filesystem, LUKS2/LVM backing and absence of swap before using its key.
Mount flags and account ownership alone do not establish encrypted storage or
full fleet qualification.

The module adds no network daemon, fleet authority, automatic proof, activation,
renewal, credential reset or boot-enablement of the authority. Existing client
binaries and public input files installed during the reviewed pilot stay under
`/var/lib`; this change does not substitute a new client executable. No device
credential, certificate, private evidence or authority address is embedded in
Nix outputs.

## Validation

Run the focused generic NixOS VM check:

```sh
nix build .#checks.x86_64-linux.kaiba-pilot-device
```

It uses synthetic state, changes that state's contents, reboots, and checks
that the bytes and UID/GID survive with the required mount options. It also
checks that unsafe file permissions and missing state block the mount without
changing permissions or recreating state. This is a generic VM, not a Pi image
or OTP test; it does not qualify hardware encryption or real enrollment.

Evaluate the Ace and Mako configurations separately to confirm only Ace enables
the module. The new options default to disabled; explicit numeric IDs are
required when enabled so an existing identity is never silently reassigned.

## Deployment and real-host acceptance

Do not run `nixos-anywhere` on this existing device. Do not copy private state
into the repository, Nix store, build logs or a deployment machine.

Before applying this change, compare the candidate's complete system closure
against Ace's running configuration. A configuration built from current `main`
may include unrelated kernel, initrd, firmware, disk-unlock or workload changes
relative to the older running generation. Repository evaluation and the VM test
do not authorize those changes. Review a concrete deployment and recovery path
before any switch or reboot; preserve the account IDs and existing identity.

Record only public client status (including the key digest and enrollment ID),
state-file metadata and the protected mount options before and after the
approved switch/restart. Verify the same key opens and, while current authority
policy and transport access permit it, the same enrolled identity can read its
own status. Do not call `init`, create another key, re-enroll or reset an expired
challenge to make the test pass. A missing mount must leave the client refusing
key use.

Policy expiry and credential renewal are separate from filesystem persistence.
Successful boot does not renew authorization, turn local `verified` status into
live membership, or close any full fleet-admission condition. Ace's actual
restart and NixOS-switch results remain pending the reviewed deployment.
