{
  ...
}:
{
  imports = [
    ../../modules/users/adam.nix
  ];

  # This is the initial version of nixOS that was installed on these systems.
  system.stateVersion = "25.11";
  boot.consoleLogLevel = 4;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  networking.firewall.enable = true;
  networking.nameservers = [
    "8.8.8.8"
    "8.8.4.4"
    "2001:4860:4860::8888"
    "2001:4860:4860::8844"
  ];

  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
  };

  services.pcscd.enable = true;

  # Needed for VS Code.
  programs.nix-ld.enable = true;
}
