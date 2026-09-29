#!/usr/bin/env bash
# Usage as root on Ace: activate-ace-identity-pilot.sh CANDIDATE PREVIOUS test|switch
set -euo pipefail
candidate=$1
previous=$2
mode=$3
test "$(id -u)" = 0
case "$candidate" in /nix/store/*-nixos-system-ace-*) ;; *) exit 2;; esac
case "$previous" in /nix/store/*-nixos-system-ace-*) ;; *) exit 2;; esac
case "$mode" in test|switch) ;; *) exit 2;; esac
test -x "$candidate/bin/switch-to-configuration"
test -x "$previous/bin/switch-to-configuration"
current=$(readlink -f /run/current-system)
test "$current" = "$previous" || test "$current" = "$candidate"
test "$(readlink -f /nix/var/nix/profiles/system)" = "$previous"

# Refuse any incidental change to boot/storage or existing service definitions.
for entry in kernel initrd kernel-modules; do
  test "$(readlink -f "$candidate/$entry")" = "$(readlink -f "$previous/$entry")"
done
for entry in etc/fstab etc/crypttab \
  etc/systemd/system/hydra-server.service \
  etc/systemd/system/hydra-evaluator.service \
  etc/systemd/system/hydra-queue-runner.service \
  etc/systemd/system/postgresql.service \
  etc/systemd/system/sshd.service \
  etc/systemd/system/kaiba-pilot-existing-state.service \
  'etc/systemd/system/var-lib-kaiba\x2dpilot\x2ddevice.mount'; do
  if test -e "$previous/$entry"; then
    cmp "$previous/$entry" "$candidate/$entry"
  else
    test ! -e "$candidate/$entry"
  fi
done
test "$(stat -c '%u:%g:%a:%h' /var/lib/kaiba-pilot-device/state.json)" = 994:988:600:1
test -z "$(swapon --show --noheadings)"
systemctl is-active --quiet hydra-server postgresql sshd

# Preserve this exact current-layout system for recovery before activation.
nix-store --add-root /nix/var/nix/gcroots/kaiba-identity-pilot-before \
  --realise "$previous" >/dev/null

# Keep both automounts active, with this shell holding the actual firmware FS.
systemctl start boot.automount
cd /boot
systemctl is-active --quiet boot.automount
firmware_source=$(findmnt --fstab -n -o SOURCE --mountpoint /boot/firmware)
test -b "$firmware_source"
systemctl start boot-firmware.automount
cd /boot/firmware
systemctl is-active --quiet boot.automount boot-firmware.automount
test "$(findmnt -n -t vfat -o SOURCE --mountpoint /boot/firmware)" = \
  "$(readlink -f "$firmware_source")"

if test "$mode" = switch; then
  nix-env --profile /nix/var/nix/profiles/system --set "$candidate"
fi
"$candidate/bin/switch-to-configuration" "$mode"
test "$(readlink -f /run/current-system)" = "$candidate"
systemctl is-active --quiet hydra-server postgresql sshd
test "$(stat -c '%u:%g:%a:%h' /var/lib/kaiba-pilot-device/state.json)" = 994:988:600:1
test "$(systemctl --failed --no-legend --plain | wc -l)" = 0
echo "identity-pilot activation completed: $mode"
