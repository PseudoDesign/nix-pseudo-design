{
  description = "Nix infrastructure for pseudo.design";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
    nixos-raspberrypi.url = "github:ams-tech/nixos-raspberrypi/topic/rpi-otp-private-key";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixos-raspberrypi/nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      nixos-raspberrypi,
      disko,
      home-manager,
      ...
    }:
    let
      mkPkgs =
        system:
        import nixpkgs {
          inherit system;
        };

      hasUpstreamPackages = system: builtins.hasAttr system nixos-raspberrypi.packages;

      mkPackages =
        system:
        if hasUpstreamPackages system then
          {
            default = nixos-raspberrypi.packages.${system}.rpi-otp-derived-key;
            "rpi-otp-private-key" = nixos-raspberrypi.packages.${system}.rpi-otp-private-key;
            "rpi-otp-derived-key" = nixos-raspberrypi.packages.${system}.rpi-otp-derived-key;
          }
        else
          { };

      mkOtpLuksConfig =
        { enable }:
        { lib, pkgs, pdLuksSalt, ... }:
        {
          boot.initrd.systemd.enable = lib.mkIf enable true;
          services.rpiOtpDerivedKey = {
            inherit enable;
            generateSalt = false;
            saltFile = "/run/secrets/rpi-otp-derived-key-luks.salt";
            initrdSaltSource = pkgs.writeText "rpi-otp-derived-key-luks.salt" pdLuksSalt;
            secrets.luks = {
              format = "hex";
              path = "/run/secrets/luks.key";
              neededForBoot = true;
              before = [ "cryptsetup.target" ];
            };
          };
        };

      specialArgs = {
        inherit
          disko
          home-manager
          nixos-raspberrypi
          ;
        pdLuksSalt = "pseudo.design/luks/rootfs/v1";
      };
    in
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = mkPkgs system;
        individualChecks = import ./checks {
          inherit
            pkgs
            nixos-raspberrypi
            ;
        };
      in
      {
        packages = mkPackages system;

        checks = individualChecks // {
          tests = pkgs.symlinkJoin {
            name = "tests";
            paths = builtins.attrValues individualChecks;
          };
        };
      }
    )
    // {
    overlays.default = nixos-raspberrypi.overlays.pkgs;

    nixosModules.default = nixos-raspberrypi.nixosModules.rpi-otp-derived-key;
    nixosModules.rpi-otp-derived-key = nixos-raspberrypi.nixosModules.rpi-otp-derived-key;
    nixosModules.rpi-installer-disk = ./modules/rpi-installer-disk.nix;
    nixosModules.pd-installer = ./modules/pd-installer.nix;
    nixosModules.pd-openvpn-root-ca = ./modules/pd-openvpn-root-ca.nix;
    nixosModules.pd-openvpn-intermediate-ca = ./modules/pd-openvpn-intermediate-ca.nix;
    nixosModules.pd-openvpn-leaf = ./modules/pd-openvpn-leaf.nix;

    nixosConfigurations = {
      # "'ace' is a Raspberry Pi 5 in Adam's house."
      ace = nixos-raspberrypi.lib.nixosSystemFull {
        inherit specialArgs;
        modules = [
          ./hosts/ace
          nixos-raspberrypi.nixosModules.rpi-otp-derived-key
          (mkOtpLuksConfig { enable = true; })
          ({ pkgs, ... }: {
            environment.systemPackages = [
              pkgs.rpi-otp-private-key
              pkgs.rpi-otp-derived-key
            ];
          })
        ];
      };

      rpi5-installer = nixos-raspberrypi.lib.nixosSystemFull {
        inherit specialArgs;
        modules = [
          ./modules/pd-installer.nix
          ./modules/users/adam.nix
          ./modules/rpi5-hardware.nix
          nixos-raspberrypi.nixosModules.rpi-otp-derived-key
          (mkOtpLuksConfig { enable = false; })
          ./modules/rpi-installer-disk.nix
          ({ pkgs, ... }: {
              system.stateVersion = "25.11";
              boot.consoleLogLevel = 4;
              services.pdInstaller.enable = true;
              nix = {
                settings = {
                  experimental-features = [
                    "nix-command"
                    "flakes"
                  ];
                };
              };
              services.getty.autologinUser = "adam";
              environment.systemPackages = [
                pkgs.rpi-otp-private-key
                pkgs.rpi-otp-derived-key
              ];
              networking.nameservers = [
                "8.8.8.8"
                "8.8.4.4"
                "2001:4860:4860::8888"
                "2001:4860:4860::8844"
              ];
              networking.hostName = "rpi5-nix-installer";
              networking.firewall.enable = true;
              security.sudo.wheelNeedsPassword = false;
            })
        ];
      };
    };
  };
}
