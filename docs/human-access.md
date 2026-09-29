# Human access on Mako and Ace

Mako hosts the Kaiba human Keycloak realm and SSH user certificate issuer. Ace
receives encrypted backups using a dedicated write-only rsync account. Reusable
modules and the Linux/Nix client are owned by `kaiba-infra`; its
[human access runbook](https://github.com/PseudoDesign/kaiba-infra/blob/main/docs/human-access.md)
describes enrollment, login, revocation, and recovery.

`hosts/human-access-trust.json` records public trust generated on Mako during the
2026-09-28 initialization. Private CA keys, bootstrap administrator credentials,
and the backup SSH key were generated on Mako and remain in root-private runtime
directories. The public transport-root fingerprint and SSH signing-key fingerprint
are different and must both be pinned by the workstation client.

## Workstation access from the LAN

Public DNS resolves the identity domains to `204.8.14.108`. Connections from
inside this LAN to that public address time out, as previously observed for
Hydra, while direct HTTPS to Mako's reserved `192.168.8.247` works with the same
hostnames and valid certificates. Configure the LAN resolver to return Mako's
private address for both `auth.pseudo.design` and `ssh-ca.pseudo.design`.

The GL-BE9300 LAN router at `192.168.8.1` now has both entries under DNS →
Edit Hosts. Direct router queries and ordinary HTTPS requests from Ace verified
the private addresses and valid TLS on 2026-09-29. Existing clients may retain
the previous public address until their DNS cache expires. On a Linux workstation
using systemd-resolved, run `sudo resolvectl flush-caches`; on Windows, run
`ipconfig /flushdns` in an administrator Command Prompt. Restart the browser if
it still uses the old address, and ensure custom browser Secure DNS does not
bypass the LAN resolver.

An alternative on a NixOS workstation is:

```nix
networking.hosts."192.168.8.247" = [
  "auth.pseudo.design"
  "ssh-ca.pseudo.design"
];
```

Apply this through the workstation's normal `nixos-rebuild switch` procedure.
On other Linux distributions using Nix, add this line to `/etc/hosts` instead:

```text
192.168.8.247 auth.pseudo.design ssh-ca.pseudo.design
```

A static workstation mapping must be removed or limited to the LAN network
profile when roaming elsewhere. DHCP-distributed LAN DNS avoids that problem.
Keep the original HTTPS enrollment URL: replacing its hostname with an IP or
`.local` name breaks the expected TLS/origin configuration. The bare domain's
`/` route deliberately returns 404; the public discovery and account routes are
under `/realms/kaiba/`.

## Deployment and qualification

The reviewed infrastructure and host changes are merged and persistently deployed
on both hosts. Mako has rebooted successfully into the approved configuration.
Native checks passed HTTPS, blocked administrative routes, service restart
recovery, and encrypted backup transfer, including a backup after reboot.
Both hosts' public pilot identities and protected mount metadata were preserved;
Mako's checks also passed across reboot. The kernel image, initrd, and storage
configuration are unchanged. Dogsitting's existing 502/missing runtime password
predates this rollout; the other existing public sites and Hydra remain healthy.

Mako has 1,988 MiB RAM, four ARM64 cores, no swap, and about 195 GiB free root
space at initial inspection. After reboot and backup it retained about
895–899 MiB available RAM, with no OOM kills. Measured peaks were about 599 MiB
for Keycloak and 74 MiB for PostgreSQL; the SSH issuer peaked at about 66 MiB
before its backup restart. Keycloak's heap is 384 MiB with a 1 GiB hard limit,
PostgreSQL uses a small connection pool, and the issuer is limited to 256 MiB.
No swap is added. Heavy package builds run on Ace.

Qualification found that Pi firmware injects `cgroup_disable=memory`, preventing
the configured limits from taking effect despite kernel `CONFIG_MEMCG=y`. Mako
now appends `cgroup_enable=memory` in its generation's kernel parameters. The
[pinned kernel supports this later override](https://github.com/raspberrypi/linux/blob/8c0da7c3bb97a2e0aaa0d405d3052786c1469b35/kernel/cgroup/cgroup.c#L7080).
The approved reboot activated it: `memory` is present in
`/sys/fs/cgroup/cgroup.controllers`, and effective cgroup files confirm Keycloak's
`memory.max=1073741824`, `memory.high=805306368`, and `memory.swap.max=0`, plus the
SSH issuer's `memory.max=268435456`. Use these effective files for future checks;
the earlier disable argument can still appear in `/proc/cmdline` alongside the
later enable argument. Configured systemd properties alone do not prove enforcement.

The existing owner SSH keys remain in `modules/users/adam.nix`. Their three public
keys are explicitly recorded as the initial encryption recipients in the public
trust file; future SSH grants do not automatically grant decryption. The private
recovery keys must remain under the owner's control outside both hosts. Seven encrypted
snapshots are retained. A synthetic restore test does not establish possession
of an actual owner's decryption key.

The owner has finalized enrollment with two distinct passkey credentials. The
recorded phase is `complete`, and Keycloak has granted the SSH administrator
group. The immutable subject is `e43b0b5d-bbc8-4079-9bb7-2eb882f14514`.
The host configuration now maps
`kaiba:person:e43b0b5d-bbc8-4079-9bb7-2eb882f14514` to `adam` on both hosts;
deployment of that mapping is pending. The subject comes from
`kaiba-human-identity enroll-status`, never the username or email.

Real workstation certificate login to both hosts and decryption of a backup
using an owner's recovery key remain pending. The browser/CLI integration test
passed with virtual passkeys; the owner must still complete the workstation
checks below. Keep passkeys on independent recovery devices or accounts when
possible.

## Workstation setup (Linux with Nix)

Run these commands on your own workstation, from a reviewed checkout of this
repository. `hosts/human-access-client.json` contains only public trust and the
finalized owner's principal. It is the client configuration; the larger
`human-access-trust.json` contains additional fields the client does not accept.

```sh
nix --extra-experimental-features 'nix-command flakes' profile install \
  'github:PseudoDesign/kaiba-infra/ef8e41b97c8d7668aadd4f385e2daa0ccba383be#kaiba-login'
kaiba_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/kaiba"
install -d -m 0700 "$kaiba_config_dir"
install -m 0600 hosts/human-access-client.json "$kaiba_config_dir/login.json"
```

Use your workstation's local SSH agent. If the shell has none, start one, then
authenticate in your browser:

```sh
if [ -z "${SSH_AUTH_SOCK:-}" ]; then
  eval "$(ssh-agent -s)"
fi
kaiba login
kaiba status
```

Run this outside an SSH session or automation workspace. The private key stays
in memory and the local agent. The certificate expires within eight hours; the
client reports its public `certificateFile` path. Do not forward this agent.

Save this dedicated SSH profile as `$kaiba_config_dir/ssh_config`. If you use
`XDG_STATE_HOME`, replace `IdentityFile` with the reported `certificateFile` path.
The public certificate selects its matching agent-held private key:

```sshconfig
Host ace-human mako-human
    User adam
    IdentityFile ~/.local/state/kaiba/certificate.pub
    IdentitiesOnly yes
    ForwardAgent no
    ControlMaster no
    ControlPath none

Host ace-human
    HostName ace

Host mako-human
    HostName mako
```

After the host mapping is deployed, open fresh sessions with that profile:

```sh
ssh -F "$kaiba_config_dir/ssh_config" ace-human
ssh -F "$kaiba_config_dir/ssh_config" mako-human
```

Keep host-key verification enabled and confirm the server audit records the
certificate principal. Remove this client's agent identity when finished:

```sh
kaiba logout
```

Logout preserves unrelated agent keys and existing SSH/browser sessions. Use
`kaiba logout` before logging in again to replace an expired certificate.

## Future deployments and recovery

Preserve the running system generation, public pilot identity status, state-file
metadata, and protected mount options before test deployment. The runtime record
directory is `/var/tmp/kaiba-human-access-rollout` on each host. The pilot UID/GID
assignments remain Ace `994:988`, Mako `991:985`; private pilot state is excluded
from human-access backups and is never read by this rollout.

Before activation, compare the candidate's closure, kernel, initrd, and fstab
with the running generation. Use the existing safe boot automount sequence,
holding the firmware mount while invoking activation:

```sh
sudo bash -euc '
  if findmnt --fstab -n --mountpoint /boot >/dev/null; then
    systemctl start boot.automount
    cd /boot
    systemctl is-active --quiet boot.automount
  else
    test "$(findmnt -n -o TARGET --target /boot)" = /
    cd /boot
  fi
  firmware_source=$(findmnt --fstab -n -o SOURCE --mountpoint /boot/firmware)
  test -b "$firmware_source"
  systemctl start boot-firmware.automount
  cd /boot/firmware
  systemctl is-active --quiet boot-firmware.automount
  test "$(findmnt -n -t vfat -o SOURCE --mountpoint /boot/firmware)" = \
    "$(readlink -f "$firmware_source")"
  "/nix/store/<reviewed-system>/bin/switch-to-configuration" test
'
```

Ace has an outer `/boot` automount and uses the `disk-main-boot` label. Mako
keeps `/boot` on root and automounts only `/boot/firmware`, using the
`disk-nvme0-luks-boot` label. The guard derives the expected source from each
host's unchanged fstab; do not assume their boot layouts match.

Verify the new services, HTTPS, memory, encrypted backup, existing Hydra/web
services, and unchanged public pilot status before `switch`. Do not start
`boot-firmware.mount` directly. On Ace, generations before the root-backed home
migration cannot be booted unchanged. A system rollback also does not revert
Keycloak/PostgreSQL state; use the identity restore procedure for database changes.
