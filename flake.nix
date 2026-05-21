{
  description = "NixOS Raspberry Pi 5 hosts for pseudo.design";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    nixos-raspberrypi.url = "github:ams-tech/nixos-raspberrypi/topic/rpi-otp-private-key";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixos-raspberrypi/nixpkgs";
    };

    pd-pki.url = "github:PseudoDesign/nix-pd-pki";
  };

  outputs =
    {
      self,
      disko,
      nixos-raspberrypi,
      nixpkgs,
      pd-pki,
      ...
    }:
    let
      lib = nixpkgs.lib;

      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];

      specialArgs = {
        inherit disko nixos-raspberrypi;
        pdPki = pd-pki;
      };

      mkRpi5LuksSystem =
        modules:
        nixos-raspberrypi.lib.nixosSystemFull {
          inherit specialArgs;
          modules = [
            self.nixosModules.rpi5-luks-hardware
            ./modules/users/adam.nix
          ]
          ++ modules;
        };

      mkRpi5Host =
        hostModule:
        mkRpi5LuksSystem [
          self.nixosModules.pseudo-design-device-identity
          self.nixosModules.pseudo-design-auth-server
          ./modules/profiles/base-rpi.nix
          hostModule
        ];

    in
    {
      checks = forAllSystems (
        system:
        import ./checks/default.nix {
          inherit
            nixpkgs
            pd-pki
            self
            system
            ;
        }
      );

      packages = forAllSystems (_system: { });

      apps = forAllSystems (_system: { });

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.nixos-anywhere
              pkgs.openssl
              pkgs.openssh
              pkgs.step-cli
              pd-pki.packages.${system}.pd-pki-operator
              pd-pki.packages.${system}.pd-pki-signing-tools
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
