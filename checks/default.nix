{ pkgs, nixos-raspberrypi, ... }:
{
  pd-openvpn-pki = pkgs.callPackage ./pd-openvpn-pki.nix { };
  pd-nix-installer = pkgs.callPackage ./pd-nix-installer.nix { inherit nixos-raspberrypi; };
  rpi-otp-derived-key-luks = pkgs.callPackage ./rpi-otp-luks-key.nix { inherit nixos-raspberrypi; };
}
