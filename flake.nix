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
        pdCa = final.callPackage ./packages/pki/pd-ca.nix { };
        pdOpenvpnInstallPki = final.callPackage ./packages/pki/pd-openvpn-install-pki.nix { };
        rpi-otp-private-key = final.callPackage ./packages/rpi-otp-private-key.nix { };
        rpi-otp-derived-key = final.callPackage ./packages/rpi-otp-derived-key.nix { };
        rpi-otp-provision-private-key = final.callPackage ./packages/rpi-otp-provision-private-key.nix { };
        rpi-otp-write-derived-key = final.callPackage ./packages/rpi-otp-write-derived-key.nix {
          derivePackage = final.rpi-otp-derived-key;
        };
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

      managedHostNames = [
        "ace"
        "seepho"
        "mako"
        "tense"
      ];

      rpiOtpPackagesModule =
        { pkgs, ... }:
        {
          environment.systemPackages = [
            pkgs.rpi-otp-private-key
            pkgs.rpi-otp-derived-key
            pkgs.rpi-otp-provision-private-key
          ];
        };

      mkManagedHost =
        hostName:
        nixos-raspberrypi.lib.nixosSystemFull {
          inherit specialArgs;
          modules = [
            overlayModule
            (./. + "/hosts/${hostName}")
            ./modules/rpi-otp-luks-key.nix
            rpiOtpPackagesModule
          ];
        };
    in
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = mkPkgs system;
        individualChecks = import ./checks { inherit pkgs; };
      in
      {
        packages = {
          default = pkgs.rpi-otp-derived-key;
          "pd-ca" = pkgs.pdCa;
          "pd-openvpn-install-pki" = pkgs.pdOpenvpnInstallPki;
          "rpi-otp-private-key" = pkgs.rpi-otp-private-key;
          "rpi-otp-derived-key" = pkgs.rpi-otp-derived-key;
          "rpi-otp-provision-private-key" = pkgs.rpi-otp-provision-private-key;
          "rpi-otp-write-derived-key" = pkgs.rpi-otp-write-derived-key;
        };

        checks = individualChecks // {
          tests = pkgs.symlinkJoin {
            name = "tests";
            paths = builtins.attrValues individualChecks;
          };
        };
      }
    )
    // {
    overlays.default = overlay;

    nixosModules.default = ./modules/rpi-otp-luks-key.nix;
    nixosModules.rpi-otp-luks-key = ./modules/rpi-otp-luks-key.nix;
    nixosModules.rpi-installer-disk = ./modules/rpi-installer-disk.nix;
    nixosModules.pd-openvpn-client = ./modules/openvpn/client.nix;
    nixosModules.pd-openvpn-server = ./modules/openvpn/server.nix;
    nixosModules.pd-installer = ./modules/pd-installer.nix;

    nixosConfigurations =
      builtins.listToAttrs (
        map (hostName: {
          name = hostName;
          value = mkManagedHost hostName;
        }) managedHostNames
      )
      // {
        rpi5-installer = nixos-raspberrypi.lib.nixosSystemFull {
        inherit specialArgs;
        modules = [
          overlayModule
          ./modules/pd-installer.nix
          ./modules/users/adam.nix
          ./modules/rpi5-hardware.nix
          ./modules/rpi-otp-luks-key.nix
          ./modules/rpi-installer-disk.nix
          (
            { pkgs, ... }:
            {
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
            }
          )
        ];
      };
      };
  };
}
