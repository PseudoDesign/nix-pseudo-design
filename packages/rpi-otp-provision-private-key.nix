{
  writeShellApplication,
  lib,
  rpi-otp-private-key,
  openssl
}:
let
  privateKeyExe = lib.getExe rpi-otp-private-key;
in
writeShellApplication {
  name = "rpi-otp-provision-private-key";
  runtimeInputs = [ openssl ];
  text = ''
    privateKeyHex="$(openssl rand -hex 32)"
    if [ "''${#privateKeyHex}" -ne 64 ]; then
      echo "Failed to generate a 32-byte private key."
      exit 2
    fi

    ${privateKeyExe} -w "''${privateKeyHex}"
  '';
  meta = {
    description = "Provision a random Raspberry Pi OTP private key.";
  };
}
