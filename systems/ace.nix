{
  inputs,
  ...
}:
inputs.nixos-raspberrypi.lib.nixosSystem 
{
  specialArgs = inputs;
  modules = [
    ./hardware-modules/rpi5-encrypted-nvme.nix
    inputs.disko.nixosModules.disko
    ({ pkgs, ...}: {
      environment.systemPackages = [
        pkgs.raspberrypi-eeprom
        # Add other packages here
      ];
      imports = with inputs.nixos-raspberrypi.nixosModules; [
        raspberry-pi-5.base
        raspberry-pi-5.bluetooth
      ];
      boot.loader.raspberry-pi.bootloader = "kernel";
    })
    ({ ... }: {
      # This is the initial version of nixOS that was installed on this system.
      system.stateVersion = "25.11";
      nix = {
        settings = {
          experimental-features = [ "nix-command" "flakes" ];
        };
      };
      networking.hostName = "ace";
      networking.firewall.enable = true;
      networking.firewall.allowedTCPPorts = [ 80 443 ];
      users.users.adam = {
        isNormalUser = true;
        extraGroups = [
          "wheel"
        ];
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJMjtOqSWLDq79t/9XljmBrfBVm8deQJdOQmTV7c45Ni adam" # content of authorized_keys file
        ];
      };
      security.sudo.wheelNeedsPassword = false;
      services.openssh.enable = true;
      services.avahi = {
        enable = true;
        nssmdns4 = true;
      };
      services.pcscd.enable = true;
    })
    ({ ... }: {
      disko.devices = {
        disk = {
          nvme0n1 = {
            type = "disk";
            device = "/dev/nvme0n1";
            content = {
              type = "gpt";
              partitions = {
                luks = {
                  size = "100%";
                  label = "luks";
                };
              };
            };
          };
        };
      };
      fileSystems = {
        "/boot/firmware" = {
          device = "/dev/disk/by-uuid/2175-794E";
          fsType = "vfat";
          options = [
            "noatime"
            "noauto"
            "x-systemd.automount"
            "x-systemd.idle-timeout=1min"
          ];
        };
        "/" = {
          device = "/dev/disk/by-uuid/44444444-4444-4444-8888-888888888888";
          fsType = "ext4";
          options = [ "noatime" ];
        };
      };
    })
  ];
}