{ lib, pdPki, ... }:

let
  rootInventoryRoot = pdPki + "/inventory/root-ca";
  rootInventoryEntries = builtins.attrNames (builtins.readDir rootInventoryRoot);
  rootFingerprint =
    if rootInventoryEntries == [ ] then
      null
    else
      builtins.head (lib.sort (left: right: left < right) rootInventoryEntries);
in
{
  imports = [ ./rpi-common.nix ];

  services.pseudoDesign.deviceIdentity = {
    enable = true;
  }
  // lib.optionalAttrs (rootFingerprint != null) {
    inherit rootFingerprint;
  };

}
