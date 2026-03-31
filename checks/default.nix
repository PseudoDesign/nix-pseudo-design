{ pkgs, ... }:
{
  rpi-otp-luks-key = pkgs.callPackage ./rpi-otp-luks-key.nix {};
}