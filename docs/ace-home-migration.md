# Consolidating Ace's home volume into root

This is a migration of an existing installation, not a fresh disk layout. Do
not run disko or nixos-anywhere. The configuration removes only the separate
`/home` mount; it does not copy files, delete a logical volume, or resize root.
Complete the data cutover before activating it.

## Inspected baseline — 2026-09-28 UTC

Ace has one 238.5 GiB NVMe device. Its existing LUKS container backs the `pool`
volume group, with two linear ext4 logical volumes and no free extents:

| Logical volume | Size | Filesystem use | Mount |
| --- | ---: | ---: | --- |
| `pool/rootfs` | 80 GiB | about 46.2 GiB | `/` |
| `pool/home` | about 156.5 GiB | about 7.6 GiB | `/home` |

Root has about 28 GiB available, enough for the home data. `/home/adam` is owned
by UID 1000/GID 100 with mode 0700. There are no nested mounts beneath `/home`.
Recheck these observations and free space immediately before migration.
The underlying root `/home` contains only an empty `adam` directory with the
same ownership and mode (8 KiB total, no regular files or symlinks). Preserve
that underlying directory in the migration records when replacing it.

The intended result is a roughly 236.5 GiB root LV with `/home` as an ordinary
directory. The GPT, LUKS container and unlock recipe remain unchanged. Preserve
the kernel, initrd, boot filesystems, disabled swap, and enrolled pilot identity.
Never read or copy `/var/lib/kaiba-pilot-device/state.json`; compare only public
client status and the metadata described in `ace-pilot-persistence.md`.

The prepared configuration built successfully on Ace as
`/nix/store/80qsyq2nvpx0d8g0c5jwm6912qmp9yc4-nixos-system-ace-26.05.20260807.ee48b14`.
The closure comparison against the running `7jncgk...` generation changes only
the filesystem table, generated `/etc`, and system wrapper. The kernel and
initrd are identical, and the only fstab change removes `/dev/pool/home`.
The candidate is rooted at `/var/tmp/ace-home-migration-candidate`; it has not
been activated. No home files or LVM allocations have been changed.

## Prepare and copy

1. Build the candidate and compare its closure, kernel, initrd, LUKS settings,
   and pilot units against the running system. Record the old system profile,
   filesystem/LVM metadata, and public pilot status in a root-only migration
   directory outside `/home`. Save LVM metadata with `vgcfgbackup`; this is not
   a backup of home files.
2. Arrange a short maintenance window for user sessions and Hydra. Finish
   running builds, pause the queue runner and evaluator, and prevent new work
   during the copy. Leave PostgreSQL and the web service available if possible.
   Keep the disk guards in force. Monitor free space throughout.
3. Inspect the underlying root `/home` through a nonrecursive bind of `/` in a
   private mount namespace. If it contains files, stop and reconcile them before
   copying. Do not recursively expose or copy the enrolled pilot state.
4. Copy the mounted home filesystem to a root-only staging directory on root
   using `rsync -aHAXSx --numeric-ids`. Preserve all users' files, ownership,
   permissions, ACLs, extended attributes, hardlinks, sparse files and symlinks.
   Keep file names and contents out of public logs.

## Cut over while retaining the original LV

1. Run the cutover from a root system service outside user sessions, with its
   working directory outside `/home`. Quiesce all home users and writers; the
   current SSH session may disconnect. Final-sync the staging copy, then perform
   a checksum comparison with `rsync --checksum --dry-run --itemize-changes`
   using the same preservation flags. Store comparison output root-only and
   require no differences. Do not remove destination-only files without first
   establishing that the destination is exclusively migration staging.
2. Unmount `/home` normally. If it is busy, stop and identify the remaining
   users; do not force or lazily unmount it. Atomically move the staged tree to
   the underlying `/home`, preserving its root-owned 0755 top-level directory.
   Keep `pool/home` intact and mount it read-only at a private recovery location
   for the final comparison.
3. Test-activate the candidate using the exact boot-automount preparation in
   `hydra-live-rollout.md`. Confirm that `/home/adam` is on `pool/rootfs`, the
   new fstab has no separate home entry, SSH works in a new connection, file
   checksums and metadata match, pilot status is unchanged, and Hydra is healthy.
4. Create and verify a root-only archive of the quiescent original home data on
   root, including ACLs and xattrs, while keeping enough free space. Record a
   checksum and validate the archive. Abort before deleting the LV if a verified
   recoverable copy cannot be retained. This same-device backup protects against
   migration mistakes, not NVMe failure.
5. Persist the candidate and verify that the real firmware partition has a boot
   entry for it. A controlled reboot while the old LV still exists is the
   strongest boot check. Verify the same identity and home files afterwards.
   Obtain approval for any reboot separately if it was not included in the
   maintenance window.

## Reclaim the space

Only proceed after the copied data, new SSH login, persistent configuration and
backup are verified. Unmount every recovery view of `pool/home`, verify that it
has no users or open device holders, and confirm the exact source LV again.

The irreversible operations are:

```sh
lvremove /dev/pool/home
lvextend -l +100%FREE /dev/pool/rootfs
resize2fs /dev/pool/rootfs
```

Do not use force flags. Once the old extents are allocated to root, restoring
old LVM metadata is unsafe and does not recover home data. If filesystem growth
fails after successful LV growth, leave the enlarged LV intact, diagnose the
failure, and retry the filesystem growth; never shrink it back as a shortcut.

Verify the final LV and filesystem sizes, root-backed `/home`, metadata, public
pilot status and protected mount, disabled swap, and absence of failed units.
Resume Hydra and confirm its evaluator, queue, notifications and cache publisher
work. Retain the verified home archive until the owner accepts the migration.

## Recovery boundary

Before deleting `pool/home`, recover by quiescing home users, reconciling any
writes made to the new home directory, and restoring the old mount and system
configuration. Do not hide new files by mounting the old filesystem over them.

After deletion, ordinary NixOS rollback does **not** undo this storage change.
Older generations requiring `/dev/pool/home` can enter emergency mode. Use a
known-good generation that does not require that volume. To restore older
software, rebuild its configuration with the new home layout before activating
it. Do not select the legacy boot entries blindly or delete them until a
replacement recovery path is verified.

References: [LVM growth](https://man7.org/linux/man-pages/man8/lvextend.8.html)
and [online ext4 growth](https://man7.org/linux/man-pages/man8/resize2fs.8.html).
