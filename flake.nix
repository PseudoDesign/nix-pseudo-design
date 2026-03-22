{
  description = "Nix infrastructure for pseudo.design";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
    nixos-raspberrypi.url = "github:ams-tech/nixos-raspberrypi/rpi-otp-private-key";
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
      
    }
  ) //
  {
      nixosConfigurations = {
        # "'ace' is a Raspberry Pi 5 in Adam's house."
        ace = nixos-raspberrypi.lib.nixosSystemFull {
          specialArgs = inputs;
          modules = [
            ({ config, pkgs, lib, nixos-raspberrypi, ... }: {
              imports = with inputs.nixos-raspberrypi.nixosModules; [
                  ./hosts/ace
              ];
            })
          ];
        };
      };
  };
  
}
