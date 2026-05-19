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
      lib = nixpkgs.lib;

      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];

      specialArgs = {
        inherit disko nixos-raspberrypi;
      };

      mkRpi5System =
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
        mkRpi5System [
          self.nixosModules.pseudo-design-device-identity
          self.nixosModules.pseudo-design-auth-server
          ./modules/profiles/base-rpi.nix
          hostModule
        ];

      mkRpi5OfflineCaHost =
        hostModule:
        mkRpi5System [
          self.nixosModules.pseudo-design-offline-ca
          ./modules/profiles/rpi-common.nix
          hostModule
        ];

      mkRootCaVm =
        system:
        lib.nixosSystem {
          inherit specialArgs system;
          modules = [
            self.nixosModules.pseudo-design-offline-ca
            ./modules/users/adam.nix
            ./modules/profiles/rpi-common.nix
            ./hosts/rootca
            ./hosts/rootca/vm.nix
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

      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        rec {
          pseudo-design-ca-tools = pkgs.callPackage ./packages/pseudo-design-ca-tools { };
          default = pseudo-design-ca-tools;
        }
      );

      apps = forAllSystems (
        system:
        let
          caTools = self.packages.${system}.pseudo-design-ca-tools;
          mkCaApp = name: description: {
            type = "app";
            program = "${caTools}/bin/${name}";
            meta.description = description;
          };
          rootcaVm = self.nixosConfigurations.rootca-vm.config.system.build.vm;
        in
        {
          ca-bootstrap = mkCaApp "pseudo-design-ca-bootstrap" "Bootstrap the pseudo.design offline CA state";
          ca-create-intermediate-csr = mkCaApp "pseudo-design-ca-create-intermediate-csr" "Generate an online intermediate CA CSR and private key";
          ca-export = mkCaApp "pseudo-design-ca-export" "Export pseudo.design CA artifacts for transfer";
          ca-install-intermediate-cert = mkCaApp "pseudo-design-ca-install-intermediate-cert" "Install a signed online intermediate CA certificate";
          ca-install-public-artifacts = mkCaApp "pseudo-design-ca-install-public-artifacts" "Install pseudo.design public CA artifacts into the repo";
          ca-mint-token = mkCaApp "pseudo-design-ca-mint-token" "Mint a pseudo.design device enrollment token";
          ca-sign-intermediate = mkCaApp "pseudo-design-ca-sign-intermediate" "Sign an online intermediate CA CSR with the offline root";
        }
        // lib.optionalAttrs (system == "x86_64-linux") {
          rootca-vm = {
            type = "app";
            program = lib.getExe rootcaVm;
            meta.description = "Run the pseudo.design root CA NixOS VM";
          };
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
              pkgs.openssl
              pkgs.openssh
              pkgs.step-cli
              self.packages.${system}.pseudo-design-ca-tools
            ];
          };
        }
      );

      nixosModules = {
        rpi5-luks-hardware = ./modules/hardware/rpi5-luks.nix;
        pseudo-design-auth-server = ./modules/services/pseudo-design-auth-server.nix;
        pseudo-design-device-identity = ./modules/services/pseudo-design-device-identity.nix;
        pseudo-design-offline-ca = ./modules/services/pseudo-design-offline-ca.nix;
      };

      nixosConfigurations = {
        ace = mkRpi5Host ./hosts/ace;
        mako = mkRpi5Host ./hosts/mako;
        rootca = mkRpi5OfflineCaHost ./hosts/rootca;
        rootca-vm = mkRootCaVm "x86_64-linux";
      };
    };
}
