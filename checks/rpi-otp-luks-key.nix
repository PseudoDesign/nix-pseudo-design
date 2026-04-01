{ lib, testers }:
let
  # Mock overlays for our system
  mocksOverlay = final: prev: {
    rpi-otp-private-key = final.callPackage ./packages/rpi-otp-private-key.nix { };
  };
in
testers.runNixOSTest {
  name = "Test for rpi-otp-luks-key initrd service";
  nodes.rpi =
    { ... }:
    {
      nixpkgs.overlays = [ mocksOverlay ];
      imports = [ ../modules/rpi-otp-luks-key ];
    };

  testScript = ''
    start_all()
  '';
}
