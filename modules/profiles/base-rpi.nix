{
  boot.consoleLogLevel = 4;

  system.stateVersion = "25.11";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  networking.firewall.enable = true;

  security.sudo.wheelNeedsPassword = false;

  # The Raspberry Pi package assumes Raspberry Pi OS's `sudo` group. These
  # NixOS hosts use `wheel`; keep debugfs root-only instead of granting a new
  # group access. An explicit file replaces the package's same-named rule.
  environment.etc."tmpfiles.d/sys-kernel-debug.conf".text = ''
    d! /sys/kernel/debug 0700 root root -
  '';

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
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };
}
