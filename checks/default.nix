{ pkgs, ... }:
{
  pd-installer = pkgs.callPackage ./pd-installer.nix { };
  rpi-otp-luks-key = pkgs.callPackage ./rpi-otp-luks-key.nix { };
}
