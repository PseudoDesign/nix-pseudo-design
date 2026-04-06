{
  writeShellApplication,
  coreutils,
  openvpn,
}:
writeShellApplication {
  name = "pd-openvpn-generate-tls-crypt-key";
  runtimeInputs = [
    coreutils
    openvpn
  ];
  text = ''
    readonly EX_USAGE=64
    readonly EX_CANTCREAT=73

    usage() {
      cat <<'EOF'
Usage: pd-openvpn-generate-tls-crypt-key [--force] OUT_FILE

Generate an OpenVPN tls-crypt shared key at OUT_FILE.

The helper refuses to overwrite an existing file unless --force is passed.
EOF
    }

    force=0

    if [ "''${1-}" = "--help" ] || [ "''${1-}" = "-h" ]; then
      usage
      exit 0
    fi

    if [ "''${1-}" = "--force" ]; then
      force=1
      shift
    fi

    if [ "$#" -ne 1 ]; then
      usage >&2
      exit "$EX_USAGE"
    fi

    outFile="$1"
    parentDir="$(${coreutils}/bin/dirname "$outFile")"

    if [ -e "$outFile" ] && [ "$force" -ne 1 ]; then
      echo "Refusing to overwrite existing tls-crypt key: $outFile" >&2
      exit "$EX_CANTCREAT"
    fi

    ${coreutils}/bin/install -d -m 0700 "$parentDir"
    tmpFile="$(${coreutils}/bin/mktemp "$parentDir/.tls-crypt.XXXXXX")"

    cleanup() {
      ${coreutils}/bin/rm -f "$tmpFile"
    }
    trap cleanup EXIT

    openvpn --genkey secret "$tmpFile"
    ${coreutils}/bin/chmod 0600 "$tmpFile"
    ${coreutils}/bin/mv -f "$tmpFile" "$outFile"

    trap - EXIT
  '';

  meta = {
    description = "Generate an OpenVPN tls-crypt shared key.";
  };
}
