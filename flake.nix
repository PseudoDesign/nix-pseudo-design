{
  description = "NixOS Raspberry Pi 5 hosts for pseudo.design";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    nixos-raspberrypi.url = "github:ams-tech/nixos-raspberrypi/codex/rpi-otp-upstream-improvements";

    kaiba-infra = {
      url = "github:PseudoDesign/kaiba-infra/f6d3edf36980734095fd7bfc18b0a2e7b4a08f4f";
      inputs.nixpkgs.follows = "nixos-raspberrypi/nixpkgs";
    };

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
      kaiba-infra,
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
        inherit
          crtvar
          disko
          dogsitting
          kaiba-infra
          nixos-raspberrypi
          self
          ;
      };

      mkRpi5Host =
        {
          hostModule,
          hardwareModule ? self.nixosModules.rpi5-luks-hardware,
        }:
        nixos-raspberrypi.lib.nixosSystemFull {
          inherit specialArgs;
          modules = [
            hardwareModule
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
        ace-legacy-luks-key = import ./tests/ace-legacy-luks-key.nix {
          pkgs = import nixpkgs { inherit system; };
        };
        kaiba-pilot-device = import ./tests/kaiba-pilot-device.nix {
          pkgs = import nixpkgs { inherit system; };
        };
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
      nixosModules.kaiba-pilot-device = ./modules/services/kaiba-pilot-device.nix;

      nixosConfigurations = {
        ace = mkRpi5Host {
          hostModule = ./hosts/ace;
          hardwareModule = ./hosts/ace/hardware.nix;
        };
        mako = mkRpi5Host { hostModule = ./hosts/mako; };
      };
    };
}
