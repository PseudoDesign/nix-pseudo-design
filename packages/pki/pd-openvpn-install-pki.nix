{
  writeShellApplication,
  coreutils,
  openssl,
}:
writeShellApplication {
  name = "pd-openvpn-install-pki";
  runtimeInputs = [
    coreutils
    openssl
  ];
  text = ''
    readonly EX_USAGE=64
    readonly EX_DATAERR=65
    readonly EX_NOINPUT=66

    detect_staged_identity_dir() {
      local source_dir="$1"
      local candidate_dir
      local match_count=0
      local matched_dir=""

      for candidate_dir in "$source_dir"/issued/openvpn/servers/* "$source_dir"/issued/openvpn/clients/*; do
        if [ -d "$candidate_dir" ]; then
          match_count=$((match_count + 1))
          matched_dir="$candidate_dir"
        fi
      done

      if [ "$match_count" -ne 1 ]; then
        echo "Expected exactly one staged identity directory under: $source_dir/issued/openvpn" >&2
        exit "$EX_NOINPUT"
      fi

      printf '%s\n' "$matched_dir"
    }

    cert_matches_key() {
      local key_file="$1"
      local cert_file="$2"
      local tmp_dir
      local cert_public_key
      local key_public_key
      local result

      tmp_dir="$(${coreutils}/bin/mktemp -d)"
      ${openssl}/bin/openssl x509 -in "$cert_file" -pubkey -noout > "$tmp_dir/cert.pub.pem"
      ${openssl}/bin/openssl pkey -in "$key_file" -pubout > "$tmp_dir/key.pub.pem"
      cert_public_key="$(${coreutils}/bin/cat "$tmp_dir/cert.pub.pem")"
      key_public_key="$(${coreutils}/bin/cat "$tmp_dir/key.pub.pem")"

      if [ "$cert_public_key" = "$key_public_key" ]; then
        result=0
      else
        result=1
      fi

      ${coreutils}/bin/rm -rf "$tmp_dir"
      return "$result"
    }

    if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
      echo "Usage: pd-openvpn-install-pki <source-dir> <target-dir> <identity-key-source-file> [tls-crypt-source-file]" >&2
      exit "$EX_USAGE"
    fi

    sourceDir="$1"
    targetDir="$2"
    identityKeySourceFile="$3"
    tlsCryptSourceFile="''${4-}"
    parentDir="$(${coreutils}/bin/dirname "$targetDir")"
    stagedIdentityDir=""
    stagedIdentityName=""
    stagedIdentityCertFile=""
    stagedIdentityTargetDir=""
    stagedIdentityTargetKeyFile=""

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

    if [ ! -f "$identityKeySourceFile" ]; then
      echo "Missing identity key source file: $identityKeySourceFile" >&2
      exit "$EX_NOINPUT"
    fi

    if [ -n "$tlsCryptSourceFile" ] && [ ! -f "$tlsCryptSourceFile" ]; then
      echo "Missing tls-crypt source file: $tlsCryptSourceFile" >&2
      exit "$EX_NOINPUT"
    fi

    stagedIdentityDir="$(detect_staged_identity_dir "$sourceDir")"
    stagedIdentityName="''${stagedIdentityDir##*/}"
    stagedIdentityCertFile="$stagedIdentityDir/$stagedIdentityName.crt"

    if [ -f "$stagedIdentityDir/$stagedIdentityName.key" ]; then
      echo "Staged PKI source must not contain an identity private key: $stagedIdentityDir/$stagedIdentityName.key" >&2
      exit "$EX_DATAERR"
    fi

    if [ ! -f "$stagedIdentityCertFile" ]; then
      echo "Missing staged identity certificate: $stagedIdentityCertFile" >&2
      exit "$EX_NOINPUT"
    fi

    if ! cert_matches_key "$identityKeySourceFile" "$stagedIdentityCertFile"; then
      echo "Identity key source does not match staged certificate: $identityKeySourceFile" >&2
      exit "$EX_DATAERR"
    fi

    ${coreutils}/bin/install -d -m 0700 "$parentDir"
    tmpTargetDir="$(${coreutils}/bin/mktemp -d "$parentDir/.openvpn-pki.XXXXXX")"
    stagedIdentityTargetDir="$tmpTargetDir/''${stagedIdentityDir#"$sourceDir"/}"
    stagedIdentityTargetKeyFile="$stagedIdentityTargetDir/$stagedIdentityName.key"

    cleanup() {
      ${coreutils}/bin/rm -rf "$tmpTargetDir"
    }
    trap cleanup EXIT

    ${coreutils}/bin/cp -R "$sourceDir/." "$tmpTargetDir/"
    ${coreutils}/bin/install -m 0600 "$identityKeySourceFile" "$stagedIdentityTargetKeyFile"

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
