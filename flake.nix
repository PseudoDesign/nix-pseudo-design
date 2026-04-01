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
  outputs = { self, nixpkgs, flake-utils, nixos-raspberrypi, disko, home-manager, ... }@inputs: 
  flake-utils.lib.eachDefaultSystem (system:
    let 
      pkgs = import nixpkgs {
        inherit system;
      };
    in 
    {
       checks = {
        tests = pkgs.callPackage ./checks/rpi-otp-luks-key.nix {};
       };
    }
  ) //
  {
    overlays.default = final: prev: {
      rpi-otp-private-key = final.callPackage ./packages/rpi-otp-private-key.nix { };
      rpi-otp-luks-key = final.callPackage ./packages/rpi-otp-luks-key.nix {};
      rpi-otp-provision-private-key = final.callPackage ./packages/rpi-otp-provision-private-key.nix {};
    };
    
    nixosConfigurations = {
      # "'ace' is a Raspberry Pi 5 in Adam's house."
      ace = nixos-raspberrypi.lib.nixosSystemFull {
        specialArgs = inputs;
        modules = [
          ./hosts/ace
          ./modules/rpi-otp-luks-key.nix
          ({ pkgs, ... }: {
            nixpkgs.overlays = [ self.overlays.default ];
            environment.systemPackages = [
              pkgs.rpi-otp-private-key
              pkgs.rpi-otp-luks-key
              pkgs.rpi-otp-provision-private-key
            ];
          })
        ];        
      };
    
      rpi5-installer = nixos-raspberrypi.lib.nixosSystemFull  {
        specialArgs = inputs;
        modules = [
          ./modules/users/adam.nix
          ./modules/rpi5-hardware.nix
          ./modules/rpi-otp-luks-key.nix
          ./modules/rpi-installer-disk.nix
          ({ pkgs, ... }: 
          let
            installScript = pkgs.writeShellScriptBin "pd-nix-install" ''
              BRANCH="$1"
              nix run 'github:nix-community/disko/latest#disko-install' -- \
                --flake "github:pseudodesign/nix-pseudo-design/''${BRANCH}#ace" \
                --mode format \
                --disk main /dev/nvme0n1
            '';
          in
          {
            nix = {
              settings = {
                experimental-features = [ "nix-command" "flakes" ];
              };
            };
            services.getty.autologinUser = "adam";
            environment.systemPackages = [
              pkgs.rpi-otp-provision-private-key
              installScript
            ];
            nixpkgs.overlays = [ self.overlays.default ];
            networking.nameservers = [ "8.8.8.8" "8.8.4.4" "2001:4860:4860::8888" "2001:4860:4860::8844"];
            networking.hostName = "rpi5-nix-installer";
            networking.firewall.enable = true;
            security.sudo.wheelNeedsPassword = false;
          })
        ];
      };
    };
  };
}
