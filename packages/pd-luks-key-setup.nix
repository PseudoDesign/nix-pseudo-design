{
  writeShellApplication,
  lib,
  coreutils,
  rpi-otp-private-key,
  derivePackage,
  saltSource,
  keyFile,
}:
let
  privateKeyCheckExe = lib.getExe rpi-otp-private-key;
  deriveKeyExe = lib.getExe derivePackage;
in
writeShellApplication {
  name = "pd-luks-key-setup";
  runtimeInputs = [ coreutils ];
  text = ''
    readonly EX_NOPERM=77
    readonly EX_SOFTWARE=70

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

    if [ ! -r '${saltSource}' ]; then
      echo "Salt source '${saltSource}' is not readable." >&2
      exit "$EX_SOFTWARE"
    fi

    keyDir="$(${coreutils}/bin/dirname '${keyFile}')"
    ${coreutils}/bin/install -d -m 0700 "$keyDir"
    tmpKeyFile="$(${coreutils}/bin/mktemp "$keyDir/.luks.key.XXXXXX")"
    cleanup() {
      ${coreutils}/bin/rm -f "$tmpKeyFile"
    }
    trap cleanup EXIT

    ${deriveKeyExe} \
      --format hex \
      --salt-file '${saltSource}' \
      > "$tmpKeyFile"

    ${coreutils}/bin/chmod 600 "$tmpKeyFile"
    ${coreutils}/bin/mv -f "$tmpKeyFile" '${keyFile}'
    trap - EXIT
  '';

  meta = {
    description = "Derive and write the Raspberry Pi OTP-backed LUKS key file.";
  };
}
