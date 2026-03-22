{
  home-manager,
  ...
}:
{
  imports = [
    ../../modules/users/adam.nix
    ./hardware-configuration.nix
    home-manager.nixosModules.default
  ];
  # This is the initial version of nixOS that was installed on this system.
  system.stateVersion = "25.11";
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
    };
  };
  networking.hostName = "ace";
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  security.sudo.wheelNeedsPassword = false;
  services.openssh.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
  };
  services.pcscd.enable = true;

  # Home Manager integration
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.adam = import ../../home/adam.nix;
  # Needed for vscode
  programs.nix-ld.enable = true;
}