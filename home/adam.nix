# This file contains the "userspace" level configuration for the "adam" account.
# The "modules/users.nix" file actually creates those accounts on the target machine.
{ config, pkgs, ... }:
{
  # Add support for VSCode remote server
  # imports = [
  #   "${fetchTarball "https://github.com/nix-community/nixos-vscode-server/tarball/master"}/modules/vscode-server/home.nix"
  # ];

  # services.vscode-server.enable = true;

  home.username = "adam";
  home.homeDirectory = "/home/adam";

  home.stateVersion = "25.11";

  programs.bash.enable = true;

#  programs.git = {
#    enable = true;
#    settings = {
#      userName = "ams-tech";
#      userEmail = "ams-tech@users.noreply.github.com";
#    };
#  };

  home.sessionVariables = {
    EDITOR = "vim";
  };

  home.packages = with pkgs; [
    
  ];
}