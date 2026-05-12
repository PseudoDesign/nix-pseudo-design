{ lib, ... }:

let
  rootFingerprintFile = ../../ca/public/root_ca.fingerprint;
  readFingerprint =
    path: builtins.replaceStrings [ "\n" "\r" " " "\t" ] [ "" "" "" "" ] (builtins.readFile path);
in
{
  imports = [ ./rpi-common.nix ];

  services.pseudoDesign.deviceIdentity =
    {
      enable = true;
    }
    // lib.optionalAttrs (builtins.pathExists rootFingerprintFile) {
      rootFingerprint = readFingerprint rootFingerprintFile;
    };

}
