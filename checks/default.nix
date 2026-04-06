{ pkgs, ... }:
{
  openvpn-revoked-client = pkgs.callPackage ./openvpn/revoked-client.nix { };
  openvpn-smoke = pkgs.callPackage ./openvpn/smoke.nix { };
  openvpn-wrong-ca = pkgs.callPackage ./openvpn/wrong-ca.nix { };
  pd-ca = pkgs.callPackage ./pki/pd-ca.nix { };
  pd-nix-installer = pkgs.callPackage ./pd-nix-installer.nix { };
  rpi-otp-luks-key = pkgs.callPackage ./rpi-otp-luks-key.nix { };
}
