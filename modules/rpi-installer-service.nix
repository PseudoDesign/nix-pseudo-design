{ config, pkgs, ... }:

let
  imageUpgrade = pkgs.writeShellScriptBin "pd-nix-installer-upgrade" ''
    clear
    FLAKE="github:pseudodesign/nix-pseudo-design/latest#rpi5-installer"
    nixos-rebuild switch --flake "''${FLAKE}" --refresh
  '';

  installScript = pkgs.writeShellScriptBin "pd-nix-install" ''
    clear
    FLAKE="github:pseudodesign/nix-pseudo-design/latest#ace"
    DISK="/dev/nvme0n1"
    while true; do
        read -p "Install ''${FLAKE} to ''${DISK} [y/n] " yn
        case $yn in
            [Yy]* ) break;;
            [Nn]* ) exit;;
            * ) echo "Please answer yes or no.";;
        esac
    done
    nix run 'github:nix-community/disko/latest#disko-install' -- \
      --flake "''${FLAKE}" \
      --mode format \
      --disk main "''${DISK}"
  '';
in
{
  environment.systemPackages = [ installScript imageUpgrade ];

  services.getty.autologinUser = "root";

  systemd.services.auto-upgrade = {
    description = "Auto-Upgrade Service";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-user-sessions.service" "getty@tty1.service" ];
    serviceConfig = {
      User = "root";
      TTYPath = "/dev/tty1";
      StandardInput = "tty";
      StandardOutput = "tty";
      StandardError = "tty";
      TTYReset = true;
      TTYVHangup = true;
      TTYVTDisallocate = true;
      Restart = "always";
      ExecStart = "${imageUpgrade}/bin/pd-nix-installer-upgrade";
    };
  };
}