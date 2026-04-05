{
  writeShellApplication,
  lib,
  coreutils,
  rpi-otp-private-key
}:
let
  privateKeyExe = lib.getExe rpi-otp-private-key;
in
writeShellApplication {
  name = "rpi-otp-derived-key";
  runtimeInputs = [ coreutils ];
  text = ''
    salt="$1"

    # The '-c' flag ensures the key is not all 0s.
    ${privateKeyExe} -c
    otpSecret="$(${privateKeyExe})"
    printf '%s\n' "''${salt}''${otpSecret}" | sha256sum | tr -d ' -'
  '';
  meta = {
    description = "Derive a key from the Raspberry Pi OTP private key.";
  };
}
