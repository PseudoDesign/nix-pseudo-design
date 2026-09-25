{
  imports = [ ../../modules/services/kaiba-pilot-device.nix ];

  services.kaibaPilotDevice = {
    enable = true;
    # Preserve the IDs that own Ace's existing enrolled key.
    uid = 994;
    gid = 988;
  };

  networking.hostName = "ace";
}
