{
  writeShellApplication,
  lib,
  coreutils,
  derivePackage,
}:
let
  deriveKeyExe = lib.getExe derivePackage;
in
writeShellApplication {
  name = "rpi-otp-write-derived-key";
  runtimeInputs = [ coreutils ];
  text = ''
    readonly EX_USAGE=64

    if [ "$#" -ne 2 ]; then
      echo "Usage: rpi-otp-write-derived-key <salt> <key-file>" >&2
      exit "$EX_USAGE"
    fi

    salt="$1"
    keyFile="$2"
    keyDir="$(${coreutils}/bin/dirname "$keyFile")"

    ${coreutils}/bin/install -d -m 0700 "$keyDir"
    tmpKeyFile="$(${coreutils}/bin/mktemp "$keyDir/.derived.key.XXXXXX")"
    cleanup() {
      ${coreutils}/bin/rm -f "$tmpKeyFile"
    }
    trap cleanup EXIT

    ${deriveKeyExe} "$salt" > "$tmpKeyFile"
    ${coreutils}/bin/chmod 600 "$tmpKeyFile"
    ${coreutils}/bin/mv -f "$tmpKeyFile" "$keyFile"
    trap - EXIT
  '';

  meta = {
    description = "Derive and atomically write a key file from the Raspberry Pi OTP private key.";
  };
}
