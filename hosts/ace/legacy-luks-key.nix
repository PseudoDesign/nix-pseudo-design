# Preserve the recipe in Ace's running generation. This predates both the
# upstream HKDF and firmware-HMAC schemes; neither reproduces this key.
{
  pkgs,
  otpHelper ? pkgs.rpi-otp-private-key,
}:
pkgs.writeShellScriptBin "ace-legacy-luks-key" ''
  set -euo pipefail
  ${otpHelper}/bin/rpi-otp-private-key -c
  otp_secret="$(${otpHelper}/bin/rpi-otp-private-key)"
  printf '%s\n' "default-salt''${otp_secret}" \
    | ${pkgs.coreutils}/bin/sha256sum \
    | ${pkgs.coreutils}/bin/tr -d ' -'
''
