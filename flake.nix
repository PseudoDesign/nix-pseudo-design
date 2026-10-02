{
  description = "NixOS Raspberry Pi 5 hosts for pseudo.design";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    nixos-raspberrypi.url = "github:ams-tech/nixos-raspberrypi/codex/rpi-otp-upstream-improvements";

    kaiba-infra = {
      url = "github:PseudoDesign/kaiba-infra/47347c03e7738051e221a2c60ec828131fa1c1fb";
      inputs.nixpkgs.follows = "nixos-raspberrypi/nixpkgs";
    };

    kaiba-dns.url = "github:pd-codex/nixos-kaiba-network/e1f18fbc355b70b2d87245288d4ebb837434cbdd";

    kaiba-fleet.url = "github:PseudoDesign/kaiba-fleet/d7027c24b523a1030b855ec8fe1b6582ad2ce1aa";

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
      kaiba-fleet,
      kaiba-dns,
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
          kaiba-fleet
          kaiba-dns
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
        member-identity-guard =
          let
            pkgs = import nixpkgs { inherit system; };
            python = pkgs.python3.withPackages (p: [ p.cryptography ]);
          in
          pkgs.runCommand "kaiba-member-identity-guard-tests" { nativeBuildInputs = [ python ]; } ''
            cp -r ${./hosts/mako} host
            cp ${./tests/member_identity_guard_test.py} member_identity_guard_test.py
            export KAIBA_MEMBER_GUARD="$PWD/host/member-identity-guard.py"
            python3 -B -m unittest discover -s . -p 'member_identity_guard_test.py' -v
            mkdir -p "$out"
            echo 'read-only admitted state guard fixture checks passed' > "$out/result"
          '';
        rpi-tmpfiles = import ./tests/rpi-tmpfiles.nix {
          pkgs = import nixpkgs { inherit system; };
          hosts = self.nixosConfigurations;
        };
        pilot-two-host = import ./tests/pilot-two-host.nix {
          pkgs = import nixpkgs { inherit system; };
          hosts = self.nixosConfigurations;
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
