{ pkgs, nixos-raspberrypi, ... }:
let
  legacyKey = import ./legacy-luks-key.nix { inherit pkgs; };
in
{
  # This is an existing installation, not the shared fresh-install disko layout.
  imports = with nixos-raspberrypi.nixosModules; [
    raspberry-pi-5.base
    raspberry-pi-5.page-size-16k
    raspberry-pi-5.display-vc4
  ];

  boot.loader.raspberry-pi.bootloader = "kernel";
  boot.initrd.systemd = {
    enable = true;
    # Initrd construction follows ELF dependencies, not shell-script PATHs.
    initrdBin = with pkgs; [
      coreutils
      gawk
      gnugrep
      gnused
      which
      xxd
      rpi-otp-private-key
    ];
    storePaths = [
      legacyKey
      pkgs.libraspberrypi
    ];
    services.ace-legacy-luks-key = {
      description = "Preserve Ace's existing OTP-derived LUKS key";
      wantedBy = [ "initrd.target" ];
      before = [ "cryptsetup-pre.target" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        UMask = "0077";
      };
      script = ''
        set -euo pipefail
        for attempt in 1 2 3 4 5 6 7 8 9 10; do
          test -e /dev/vcio && break
          ${pkgs.coreutils}/bin/sleep 0.1
        done
        ${pkgs.coreutils}/bin/install -d -m 0700 /run/secrets
        key_file="$(${pkgs.coreutils}/bin/mktemp /run/secrets/.luks-key.XXXXXXXX)"
        trap '${pkgs.coreutils}/bin/rm -f "$key_file"' EXIT
        ${legacyKey}/bin/ace-legacy-luks-key > "$key_file"
        ${pkgs.coreutils}/bin/chmod 0600 "$key_file"
        ${pkgs.coreutils}/bin/mv -f "$key_file" /run/secrets/luks.key
        trap - EXIT
      '';
    };
  };
  boot.initrd.luks.devices.crypted = {
    device = "/dev/disk/by-partlabel/disk-main-luks";
    keyFile = "/run/secrets/luks.key";
    allowDiscards = true;
    fallbackToPassword = false;
  };

  fileSystems = {
    "/" = {
      device = "/dev/pool/rootfs";
      fsType = "ext4";
      options = [ "defaults" ];
    };
    "/home" = {
      device = "/dev/pool/home";
      fsType = "ext4";
    };
    "/boot" = {
      device = "/dev/disk/by-partlabel/disk-main-ESP";
      fsType = "vfat";
      options = [
        "noatime"
        "noauto"
        "x-systemd.automount"
        "x-systemd.idle-timeout=1min"
        "umask=0077"
      ];
    };
    "/boot/firmware" = {
      device = "/dev/disk/by-partlabel/disk-main-boot";
      fsType = "vfat";
      options = [
        "noatime"
        "noauto"
        "x-systemd.automount"
        "x-systemd.idle-timeout=1min"
      ];
    };
  };
  swapDevices = [ ];
  # Preserve config.txt on the actual boot partition (disk-main-boot).
  # The ESP contains an older, shadowed /firmware copy with different settings.
  hardware.raspberry-pi.config.all.base-dt-params = {
    pciex1 = {
      enable = true;
      value = "on";
    };
    pciex1_gen = {
      enable = true;
      value = "3";
    };
  };

  # A runtime-only compatibility probe can pipe this to cryptsetup's
  # --test-passphrase mode. Never print or persist its output in build logs.
  system.build.aceLegacyLuksKey = legacyKey;
}
