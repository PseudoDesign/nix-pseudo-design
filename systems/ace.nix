{
  inputs,
  ...
}:
inputs.nixos-raspberrypi.lib.nixosSystem {
  specialArgs = inputs;
  modules = [
    ({...}: {
      imports = with inputs.nixos-raspberrypi.nixosModules; [
        raspberry-pi-5.base
        raspberry-pi-5.bluetooth
      ];
      boot.loader.raspberry-pi.bootloader = "kernel";
    })
    ({ ... }: {
      nix = {
        settings = {
          experimental-features = [ "nix-command" "flakes" ];
        };
      };
    })
    ({ ... }: {
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
    ./rpi5-configuration.nix
  ];
}