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

    if [ "$#" -ne 2 ]; then
      echo "Usage: pd-openvpn-install-pki <source-dir> <target-dir>" >&2
      exit "$EX_USAGE"
    fi

    sourceDir="$1"
    targetDir="$2"
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

    ${coreutils}/bin/install -d -m 0700 "$parentDir"
    tmpTargetDir="$(${coreutils}/bin/mktemp -d "$parentDir/.openvpn-pki.XXXXXX")"

    cleanup() {
      ${coreutils}/bin/rm -rf "$tmpTargetDir"
    }
    trap cleanup EXIT

    ${coreutils}/bin/cp -R "$sourceDir/." "$tmpTargetDir/"
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
