{ inputs, ... }: {
  imports = with inputs.nixos-raspberrypi.nixosModules; [
    raspberry-pi-5.base
    raspberry-pi-5.bluetooth
  ];
  boot.loader.raspberry-pi.bootloader = "kernel";
  fileSystems = {
    # Do not change these once devices have been deployed!
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