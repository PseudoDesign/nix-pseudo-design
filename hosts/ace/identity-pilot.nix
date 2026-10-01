{ kaiba-fleet, ... }:
let
  # Keep the host kernel, initrd and existing application packages on their
  # reviewed pins. Only the identity runtime uses Fleet's tested SPIRE pin.
  identityPkgs = import kaiba-fleet.inputs.nixpkgs { system = "aarch64-linux"; };
in
{
  imports = [ kaiba-fleet.nixosModules.spiffe-pilot ];

  services.kaiba.identity = {
    enable = true;
    role = "standalone";
    trustDomain = "pilot.kaiba.pseudo.design";
    serverPackage = identityPkgs.spire.server;
    agentPackage = identityPkgs.spire.agent;
    pilot = {
      enable = true;
      logicalDeviceID = "ace";
      instanceID = "ace-pilot-20260929";
      probePackage = kaiba-fleet.packages.aarch64-linux.spiffe-probe;
      # Use cached upstream Python packages too; the Pi overlay otherwise
      # rebuilds Rust solely for the bootstrap helper's cryptography module.
      pythonPackage = identityPkgs.python3.withPackages (p: [ p.cryptography ]);
    };
  };
}
