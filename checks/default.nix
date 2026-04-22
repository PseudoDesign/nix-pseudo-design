{ pkgs, ... }:
{
  pd-openvpn-pki = pkgs.callPackage ./pd-openvpn-pki.nix { };
  pd-nix-installer = pkgs.callPackage ./pd-installer.nix { };
  rpi-otp-luks-key = pkgs.callPackage ./rpi-otp-luks-key.nix { };
}
