{
  lib,
  nixos-raspberrypi,
  ...
}:

{
  imports = with nixos-raspberrypi.nixosModules; [
    raspberry-pi-5.base
    raspberry-pi-5.page-size-16k
    raspberry-pi-5.display-vc4
    sd-image
  ];

  boot = {
    consoleLogLevel = 4;
    loader.raspberry-pi.bootloader = "kernel";
    supportedFilesystems = lib.mkForce [
      "ext4"
      "vfat"
    ];
    tmp.useTmpfs = true;
  };

  image.baseName = lib.mkForce "pseudo-design-rootca-rpi5-sd";

  networking.firewall.enable = true;

  system.stateVersion = "25.11";

  sdImage.compressImage = lib.mkDefault true;
}
