{
  description = "Nix infrastructure for pseudo.design";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";
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
      overlay = final: prev: {
        rpi-otp-private-key = final.callPackage ./packages/rpi-otp-private-key.nix { };
        rpi-otp-luks-key = final.callPackage ./packages/rpi-otp-luks-key.nix { };
        rpi-otp-provision-private-key = final.callPackage ./packages/rpi-otp-provision-private-key.nix { };
      };

      mkPkgs =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ overlay ];
        };

      specialArgs = {
        inherit
          disko
          home-manager
          nixos-raspberrypi
          ;
      };

      overlayModule = {
        nixpkgs.overlays = [ overlay ];
      };
    in
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = mkPkgs system;
        rpiOtpLuksKeyCheck = pkgs.callPackage ./checks/rpi-otp-luks-key.nix { };
      in
      {
        packages = {
          default = pkgs.rpi-otp-luks-key;
          "rpi-otp-private-key" = pkgs.rpi-otp-private-key;
          "rpi-otp-luks-key" = pkgs.rpi-otp-luks-key;
          "rpi-otp-provision-private-key" = pkgs.rpi-otp-provision-private-key;
        };

        checks = {
          rpi-otp-luks-key = rpiOtpLuksKeyCheck;
          tests = rpiOtpLuksKeyCheck;
        };
      }
    )
    // {
    overlays.default = overlay;

    nixosModules.default = ./modules/rpi-otp-luks-key;
    nixosModules.rpi-otp-luks-key = ./modules/rpi-otp-luks-key;

    nixosConfigurations = {
      # "'ace' is a Raspberry Pi 5 in Adam's house."
      ace = nixos-raspberrypi.lib.nixosSystemFull {
        inherit specialArgs;
        modules = [
          overlayModule
          ./hosts/ace
          ./modules/rpi-otp-luks-key
          ({ pkgs, ... }: {
            environment.systemPackages = [
              pkgs.rpi-otp-private-key
              pkgs.rpi-otp-luks-key
              pkgs.rpi-otp-provision-private-key
            ];
          })
        ];
      };

      rpi5-installer = nixos-raspberrypi.lib.nixosSystemFull {
        inherit specialArgs;
        modules = [
          overlayModule
          ./modules/rpi-installer-service.nix
          ./modules/users/adam.nix
          ./modules/rpi5-hardware.nix
          ./modules/rpi-otp-luks-key
          ./modules/rpi-installer-disk.nix
          ({ pkgs, ... }: {
              system.stateVersion = "25.11";
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
                pkgs.rpi-otp-luks-key
                pkgs.rpi-otp-provision-private-key
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
