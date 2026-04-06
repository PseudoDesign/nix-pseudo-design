{
  writeShellApplication,
  coreutils,
}:
writeShellApplication {
  name = "pd-openvpn-install-pki";
  runtimeInputs = [ coreutils ];
  text = ''
    readonly EX_USAGE=64
    readonly EX_NOINPUT=66

    if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
      echo "Usage: pd-openvpn-install-pki <source-dir> <target-dir> [tls-crypt-source-file]" >&2
      exit "$EX_USAGE"
    fi

    sourceDir="$1"
    targetDir="$2"
    tlsCryptSourceFile="''${3-}"
    parentDir="$(${coreutils}/bin/dirname "$targetDir")"

    if [ ! -d "$sourceDir" ]; then
      echo "Missing source directory: $sourceDir" >&2
      exit "$EX_NOINPUT"
    fi

    if [ ! -d "$sourceDir/bundles" ]; then
      echo "Missing staged bundles directory: $sourceDir/bundles" >&2
      exit "$EX_NOINPUT"
    fi

    if [ ! -d "$sourceDir/issued" ]; then
      echo "Missing staged issued directory: $sourceDir/issued" >&2
      exit "$EX_NOINPUT"
    fi

    if [ -n "$tlsCryptSourceFile" ] && [ ! -f "$tlsCryptSourceFile" ]; then
      echo "Missing tls-crypt source file: $tlsCryptSourceFile" >&2
      exit "$EX_NOINPUT"
    fi

    ${coreutils}/bin/install -d -m 0700 "$parentDir"
    tmpTargetDir="$(${coreutils}/bin/mktemp -d "$parentDir/.openvpn-pki.XXXXXX")"

    cleanup() {
      ${coreutils}/bin/rm -rf "$tmpTargetDir"
    }
    trap cleanup EXIT

    ${coreutils}/bin/cp -R "$sourceDir/." "$tmpTargetDir/"

    if [ -n "$tlsCryptSourceFile" ]; then
      ${coreutils}/bin/install -m 0600 "$tlsCryptSourceFile" "$tmpTargetDir/tls-crypt.key"
    fi

    ${coreutils}/bin/chmod -R u=rwX,go= "$tmpTargetDir"

    if [ -e "$targetDir" ]; then
      ${coreutils}/bin/rm -rf "$targetDir"
    fi

    ${coreutils}/bin/mv "$tmpTargetDir" "$targetDir"
    trap - EXIT
  '';

  meta = {
    description = "Install a staged OpenVPN PKI tree into a writable runtime directory.";
  };
}
