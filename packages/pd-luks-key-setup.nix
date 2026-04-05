{
  writeShellApplication,
  lib,
  rpi-otp-private-key,
  writeKeyPackage,
  salt,
  keyFile,
}:
let
  # Reuse the underlying OTP check and writer helpers so this command stays thin.
  privateKeyCheckExe = lib.getExe rpi-otp-private-key;
  writeKeyExe = lib.getExe writeKeyPackage;
in
writeShellApplication {
  name = "pd-luks-key-setup";
  text = ''
    readonly EX_NOPERM=77

    # This helper is intended for explicit root-driven recovery/debug flows.
    if [ "$EUID" -ne 0 ]; then
      echo "This command must be run as root." >&2
      exit "$EX_NOPERM"
    fi

    # Refuse to derive a key until OTP has been provisioned with a non-zero secret.
    if ! ${privateKeyCheckExe} -c >/dev/null 2>&1; then
      echo "Raspberry Pi OTP private key is not provisioned. Run pd-nix-install to provision it first." >&2
      exit 1
    fi

    # Delegate the actual atomic write to the shared helper used by initrd too.
    exec ${writeKeyExe} '${salt}' '${keyFile}'
  '';

  meta = {
    description = "Derive and write the Raspberry Pi OTP-backed LUKS key file.";
  };
}
