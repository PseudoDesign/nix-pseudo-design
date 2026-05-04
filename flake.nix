{
  description = "NixOS Raspberry Pi 5 hosts for pseudo.design";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    nixos-raspberrypi.url = "github:ams-tech/nixos-raspberrypi/topic/rpi-otp-private-key";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixos-raspberrypi/nixpkgs";
    };
  };

  outputs =
    { self, disko, nixos-raspberrypi, ... }:
    let
      specialArgs = {
        inherit disko nixos-raspberrypi;
      };

      mkRpi5Host =
        hostModule:
        nixos-raspberrypi.lib.nixosSystemFull {
          inherit specialArgs;
          modules = [
            self.nixosModules.rpi5-luks-hardware
            ./modules/profiles/base-rpi.nix
            ./modules/users/adam.nix
            hostModule
          ];
        };
    in
    {
      nixosModules.rpi5-luks-hardware = ./modules/hardware/rpi5-luks.nix;

      nixosConfigurations = {
        ace = mkRpi5Host ./hosts/ace;
        mako = mkRpi5Host ./hosts/mako;
      };
    };
}
