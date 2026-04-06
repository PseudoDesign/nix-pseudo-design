{ disko, ... }:
{
  imports = [
    disko.nixosModules.disko
  ];

  services.rpiOtpLuksKey.enable = true;

  disko.devices = {
    disk = {
      main = {
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              priority = 1;
              type = "0700";
              attributes = [
                0
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

            ESP = {
              type = "EF00";
              attributes = [
                2
              ];

              size = "1024M";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [
                  "noatime"
                  "noauto"
                  "x-systemd.automount"
                  "x-systemd.idle-timeout=1min"
                  "umask=0077"
                ];
              };
            };

            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted";
                extraOpenArgs = [ ];
                settings = {
                  keyFile = "/run/secrets/luks.key";
                  allowDiscards = true;
                };
                content = {
                  type = "lvm_pv";
                  vg = "pool";
                };
              };
            };
          };
        };
      };
    };

    lvm_vg = {
      pool = {
        type = "lvm_vg";
        lvs = {
          rootfs = {
            size = "80G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };

          home = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/home";
            };
          };
        };
      };
    };
  };
}
