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

    crtvar = {
      url = "github:ams-tech/crtvar";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      crtvar,
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
        inherit crtvar disko dogsitting nixos-raspberrypi self;
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
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          pseudo-design-site = pkgs.callPackage ./packages/pseudo-design-site.nix { };
          default = self.packages.${system}.pseudo-design-site;
        }
      );

      checks = forAllSystems (system: {
        pseudo-design-site = self.packages.${system}.pseudo-design-site;
      });

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          nixosRebuild = pkgs.writeShellScriptBin "nixos-rebuild" ''
            exec ${pkgs.nixos-rebuild-ng}/bin/nixos-rebuild-ng "$@"
          '';
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.nixos-anywhere
              pkgs.nixos-rebuild-ng
              pkgs.openssh
              pkgs.zola
              nixosRebuild
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
