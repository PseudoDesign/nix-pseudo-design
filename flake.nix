{
  description = "Nix infrastructure for pseudo.design";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";
  };
  outputs = { self, nixpkgs, flake-utils, nixos-raspberrypi }@inputs: 
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
