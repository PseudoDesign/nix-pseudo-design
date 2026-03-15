{ ... }: {
  fileSystems = {
    "/boot/firmware" = {
      device = "/dev/disk/by-uuid/FIRMWARE";
      fsType = "vfat";
      options = [
        "noatime"
        "noauto"
        "x-systemd.automount"
        "x-systemd.idle-timeout=1min"
      ];
    };
    "/" = {
      device = "/dev/disk/by-uuid/NIX_OS";
      fsType = "ext4";
      options = [ "noatime" ];
    };
  };
}