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
  };
  outputs = { self, nixpkgs, flake-utils, nixos-raspberrypi, disko, ... }@inputs: 
  {
      # Load nixOS configurations from the "systems" directory.
      nixosConfigurations = {
        ace = import ./systems/ace.nix {inherit inputs;};
      };
  } //
  flake-utils.lib.eachDefaultSystem (system:
    let 
      pkgs = import nixpkgs {
        inherit system;
      };
    in 
    {
      
    }
  );
}
