# Human access on Mako and Ace

Mako hosts the Kaiba human Keycloak realm and SSH user certificate issuer. Ace
receives encrypted backups using a dedicated write-only rsync account. Reusable
modules and the Linux/Nix client are owned by `kaiba-infra`; its
[human access runbook](https://github.com/PseudoDesign/kaiba-infra/blob/codex/passkey-human-login/docs/human-access.md)
describes enrollment, login, revocation, and recovery.

`hosts/human-access-trust.json` records public trust generated on Mako during the
2026-09-28 initialization. Private CA keys, bootstrap administrator credentials,
and the backup SSH key were generated on Mako and remain in root-private runtime
directories. The public transport-root fingerprint and SSH signing-key fingerprint
are different and must both be pinned by the workstation client.

Mako's initial inspection found 1,988 MiB RAM, about 1,300 MiB available, no swap,
four ARM64 cores, and about 195 GiB free root space. This qualifies it for a bounded
test deployment; native enrollment/issuance/backup memory peaks must still be
checked before persistent activation. Keycloak's heap is 384 MiB with a 1 GiB hard
limit, PostgreSQL uses a small connection pool, and the issuer is limited to
256 MiB. No swap is added. Heavy package builds run on Ace.

Native temporary activation passed HTTPS, blocked administrative routes, service
restart recovery, and encrypted backup transfer with matching ciphertext hashes.
Mako retained about 714–738 MiB available memory; Java used about 473 MiB RSS.
Both hosts' public pilot identity, protected mount metadata, kernel, initrd and
persistent boot profiles stayed unchanged. The real browser/CLI integration test
also passes with two virtual passkeys; the owner's hardware enrollment remains
required. Dogsitting's existing 502/missing runtime password predates this rollout;
the other existing public sites and Hydra remain healthy.

Qualification found that Pi firmware injects `cgroup_disable=memory`, preventing
the configured limits from taking effect despite kernel `CONFIG_MEMCG=y`. Mako
now appends `cgroup_enable=memory` in its generation's kernel parameters. The
[pinned kernel supports this later override](https://github.com/raspberrypi/linux/blob/8c0da7c3bb97a2e0aaa0d405d3052786c1469b35/kernel/cgroup/cgroup.c#L7080);
activating it requires a reboot.
The kernel image, initrd and storage configuration do not change. Before accepting
permanent operation, verify `memory` appears in `/sys/fs/cgroup/cgroup.controllers`,
Keycloak's `memory.max` is `1073741824`, its `memory.high` is `805306368`, its
`memory.swap.max` is `0`, and the SSH issuer's `memory.max` is `268435456`.
Check the effective cgroup files: the earlier disable argument can still appear
in `/proc/cmdline` alongside the later enable argument. Native enforcement and
post-reboot capacity checks are pending; do not infer enforcement from configured
systemd properties alone.

After qualification, Mako's original runtime was restored successfully while the
boot-parameter change awaits a scheduled reboot. Identity runtime state and the
encrypted backup are retained. Ace's backup receiver remains temporarily active.
Neither persistent boot profile has changed, and no real owner has enrolled yet.

The existing owner SSH keys remain in `modules/users/adam.nix`. Their three public
keys are explicitly recorded as the initial encryption recipients in the public
trust file; future SSH grants do not automatically grant decryption. The private recovery
keys must remain under the owner's control outside both hosts. Seven encrypted
snapshots are retained. A synthetic restore test does not establish possession
of an actual owner's decryption key.

The initial passkey owner must complete the browser enrollment ceremony and
register two distinct passkey credentials. Use independent recovery devices or
accounts when possible. Only after finalization does Keycloak grant the SSH
administrator group. Host principal mappings must use the public immutable
subject returned by `kaiba-human-identity enroll-status`, never the username.
`ownerSubject = null` keeps host certificate authentication disabled until that
subject is reviewed and committed. Both hosts then share the exact `adam` mapping.

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
  /nix/store/<reviewed-system>/bin/switch-to-configuration test
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
