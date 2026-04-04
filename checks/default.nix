{ pkgs, ... }:
{
  pd-installer-service = pkgs.callPackage ./pd-installer-service.nix { };
  rpi-otp-luks-key = pkgs.callPackage ./rpi-otp-luks-key.nix { };
}
