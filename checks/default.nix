{ pkgs, ... }:
{
  openvpn-revoked-client = pkgs.callPackage ./openvpn/revoked-client.nix { };
  openvpn-smoke = pkgs.callPackage ./openvpn/smoke.nix { };
  openvpn-wrong-ca = pkgs.callPackage ./openvpn/wrong-ca.nix { };
  pd-ca = pkgs.callPackage ./pki/pd-ca.nix { };
  pd-openvpn-identity = pkgs.callPackage ./pki/pd-openvpn-identity.nix { };
  pd-openvpn-generate-tls-crypt-key = pkgs.callPackage ./pki/pd-openvpn-generate-tls-crypt-key.nix { };
  pd-openvpn-install-pki = pkgs.callPackage ./pki/pd-openvpn-install-pki.nix { };
  pd-nix-installer = pkgs.callPackage ./pd-nix-installer.nix { };
  rpi-otp-luks-key = pkgs.callPackage ./rpi-otp-luks-key.nix { };
}
