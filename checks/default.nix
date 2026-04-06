{ pkgs, ... }:
{
  openvpn-smoke = pkgs.callPackage ./openvpn-smoke.nix { };
  pd-nix-installer = pkgs.callPackage ./pd-nix-installer.nix { };
  rpi-otp-luks-key = pkgs.callPackage ./rpi-otp-luks-key.nix { };
}
