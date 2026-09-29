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
  systemctl start boot.automount
  cd /boot
  systemctl start boot-firmware.automount
  cd /boot/firmware
  systemctl is-active --quiet boot.automount boot-firmware.automount
  test "$(findmnt -n -t vfat -o SOURCE --mountpoint /boot/firmware)" = \
    "$(readlink -f /dev/disk/by-partlabel/disk-main-boot)"
  /nix/store/<reviewed-system>/bin/switch-to-configuration test
'
```

Verify the new services, HTTPS, memory, encrypted backup, existing Hydra/web
services, and unchanged public pilot status before `switch`. Do not start
`boot-firmware.mount` directly. On Ace, generations before the root-backed home
migration cannot be booted unchanged. A system rollback also does not revert
Keycloak/PostgreSQL state; use the identity restore procedure for database changes.
