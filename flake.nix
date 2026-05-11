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
    {
      self,
      disko,
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
        inherit disko nixos-raspberrypi;
      };

      mkRpi5Host =
        hostModule:
        nixos-raspberrypi.lib.nixosSystemFull {
          inherit specialArgs;
          modules = [
            self.nixosModules.rpi5-luks-hardware
            self.nixosModules.pseudo-design-device-identity
            self.nixosModules.pseudo-design-auth-server
            ./modules/profiles/base-rpi.nix
            ./modules/users/adam.nix
            hostModule
          ];
        };
    in
    {
      checks = forAllSystems (
        system:
        import ./checks/default.nix {
          inherit nixpkgs self system;
        }
      );

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
              pkgs.step-cli
            ];
          };
        }
      );

      nixosModules = {
        rpi5-luks-hardware = ./modules/hardware/rpi5-luks.nix;
        pseudo-design-auth-server = ./modules/services/pseudo-design-auth-server.nix;
        pseudo-design-device-identity = ./modules/services/pseudo-design-device-identity.nix;
      };

      nixosConfigurations = {
        ace = mkRpi5Host ./hosts/ace;
        mako = mkRpi5Host ./hosts/mako;
      };
    };
}
