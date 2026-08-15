{
  description = "NixOS Raspberry Pi 5 hosts for pseudo.design";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    nixos-raspberrypi.url = "github:ams-tech/nixos-raspberrypi/codex/rpi-otp-upstream-improvements";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixos-raspberrypi/nixpkgs";
    };

    dogsitting = {
      url = "github:PseudoDesign/dogsitting";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      disko,
      dogsitting,
      nixos-raspberrypi,
      nixpkgs,
      ...
    }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];

      specialArgs = {
        inherit disko dogsitting nixos-raspberrypi;
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
      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.nixos-anywhere
              pkgs.openssh
            ];
          };
        }
      );

      nixosModules.rpi5-luks-hardware = ./modules/hardware/rpi5-luks.nix;

      nixosConfigurations = {
        ace = mkRpi5Host ./hosts/ace;
        mako = mkRpi5Host ./hosts/mako;
      };
    };
}
