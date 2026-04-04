{ disko, ... }:
{
  imports = [
    disko.nixosModules.disko
  ];
  disko.devices = {
    disk = {
      installer = {
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            installer-boot = {
              # label = "FIRMWARE";
              priority = 1;
              type = "0700";  # Microsoft basic data
              attributes = [
                0 # Required Partition
              ];
              size = "1024M";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot/firmware";
                mountOptions = [
                  "noatime"
                  "noauto"
                  "x-systemd.automount"
                  "x-systemd.idle-timeout=1min"
                ];
              };
            };
            installer-swap = {
              size = "2G";
              content = {
                type = "swap";
              };
            };
            installer-rootfs = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
                mountOptions = [
                  "noatime"
                ];
              };
            };
          };
        };
      };
    };
  };
}
