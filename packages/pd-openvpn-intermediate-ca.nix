{
  lib,
  coreutils,
  openssl,
  symlinkJoin,
  writeShellApplication,
  writeText,
  stateDir,
  subject,
  passphraseFile ? null,
  keyBits ? 4096,
  digest ? "sha256",
  leafDays ? 825,
}:
let
  privateDir = "${stateDir}/private";
  certDir = "${stateDir}/certs";
  csrDir = "${stateDir}/csr";
  incomingDir = "${stateDir}/incoming";
  issuedServerDir = "${stateDir}/issued/servers";
  issuedClientDir = "${stateDir}/issued/clients";
  newCertsDir = "${stateDir}/newcerts";
  databaseFile = "${stateDir}/index.txt";
  serialFile = "${stateDir}/serial";
  keyFile = "${privateDir}/intermediate-ca.key";
  csrFile = "${csrDir}/intermediate-ca.csr";
  certificateFile = "${certDir}/intermediate-ca.crt";
  rootCertificateFile = "${certDir}/root-ca.crt";
  chainFile = "${certDir}/ca-chain.crt";

  opensslConfig = writeText "pd-openvpn-intermediate-ca.cnf" ''
    [ ca ]
    default_ca = CA_default

    [ CA_default ]
    dir = ${stateDir}
    certs = ${certDir}
    new_certs_dir = ${newCertsDir}
    database = ${databaseFile}
    serial = ${serialFile}
    private_key = ${keyFile}
    certificate = ${certificateFile}
    default_md = ${digest}
    default_days = ${toString leafDays}
    policy = policy_loose
    email_in_dn = no
    copy_extensions = copy
    unique_subject = no

    [ policy_loose ]
    commonName = supplied
    countryName = optional
    stateOrProvinceName = optional
    localityName = optional
    organizationName = optional
    organizationalUnitName = optional
    emailAddress = optional

    [ server_cert ]
    subjectKeyIdentifier = hash
    authorityKeyIdentifier = keyid,issuer
    basicConstraints = critical,CA:false
    keyUsage = critical,digitalSignature,keyEncipherment
    extendedKeyUsage = serverAuth
    nsCertType = server

    [ client_cert ]
    subjectKeyIdentifier = hash
    authorityKeyIdentifier = keyid,issuer
    basicConstraints = critical,CA:false
    keyUsage = critical,digitalSignature,keyEncipherment
    extendedKeyUsage = clientAuth
    nsCertType = client
  '';

  commonScript = ''
    set -euo pipefail

    readonly stateDir=${lib.escapeShellArg stateDir}
    readonly privateDir=${lib.escapeShellArg privateDir}
    readonly certDir=${lib.escapeShellArg certDir}
    readonly csrDir=${lib.escapeShellArg csrDir}
    readonly incomingDir=${lib.escapeShellArg incomingDir}
    readonly issuedServerDir=${lib.escapeShellArg issuedServerDir}
    readonly issuedClientDir=${lib.escapeShellArg issuedClientDir}
    readonly newCertsDir=${lib.escapeShellArg newCertsDir}
    readonly databaseFile=${lib.escapeShellArg databaseFile}
    readonly serialFile=${lib.escapeShellArg serialFile}
    readonly keyFile=${lib.escapeShellArg keyFile}
    readonly csrFile=${lib.escapeShellArg csrFile}
    readonly certificateFile=${lib.escapeShellArg certificateFile}
    readonly rootCertificateFile=${lib.escapeShellArg rootCertificateFile}
    readonly chainFile=${lib.escapeShellArg chainFile}
    readonly opensslConfig=${lib.escapeShellArg opensslConfig}
    readonly subject=${lib.escapeShellArg subject}
    readonly passphraseFile=${lib.escapeShellArg (if passphraseFile == null then "" else passphraseFile)}

    declare -a passInArgs=()
    declare -a passOutArgs=()

    : \
      "$stateDir" \
      "$privateDir" \
      "$certDir" \
      "$csrDir" \
      "$incomingDir" \
      "$issuedServerDir" \
      "$issuedClientDir" \
      "$newCertsDir" \
      "$databaseFile" \
      "$serialFile" \
      "$keyFile" \
      "$csrFile" \
      "$certificateFile" \
      "$rootCertificateFile" \
      "$chainFile" \
      "$opensslConfig" \
      "$subject" \
      "$passphraseFile" \
      "''${passInArgs[*]-}" \
      "''${passOutArgs[*]-}"

    ensure_layout() {
      install -d -m 0700 "$stateDir" "$privateDir"
      install -d -m 0755 "$certDir" "$csrDir" "$incomingDir" "$issuedServerDir" "$issuedClientDir" "$newCertsDir"
      [ -e "$databaseFile" ] || : > "$databaseFile"
      [ -e "$serialFile" ] || printf '%s\n' 1000 > "$serialFile"
    }

    setup_passphrase_args() {
      passInArgs=()
      passOutArgs=()

      if [ -n "$passphraseFile" ]; then
        if [ ! -f "$passphraseFile" ]; then
          echo "Passphrase file not found: $passphraseFile" >&2
          exit 1
        fi

        passInArgs=(-passin "file:$passphraseFile")
        passOutArgs=(-aes256 -passout "file:$passphraseFile")
      fi
    }

    ensure_signing_ready() {
      if [ ! -f "$keyFile" ] || [ ! -f "$certificateFile" ] || [ ! -f "$rootCertificateFile" ]; then
        echo "Intermediate CA is not ready. Initialize it and import the root/intermediate certificates first." >&2
        exit 1
      fi
    }

    default_output_path() {
      local csrPath="$1"
      local outputDir="$2"
      local baseName

      baseName="$(basename "$csrPath")"
      baseName="''${baseName%.csr}"
      printf '%s/%s.crt\n' "$outputDir" "$baseName"
    }
  '';
in
symlinkJoin {
  name = "pd-openvpn-intermediate-ca-tools";
  paths = [
    (writeShellApplication {
      name = "pd-openvpn-intermediate-ca-init";
      runtimeInputs = [
        coreutils
        openssl
      ];
      text = commonScript + ''
        ensure_layout
        setup_passphrase_args

        if [ ! -f "$keyFile" ]; then
          umask 077
          openssl genrsa "''${passOutArgs[@]}" -out "$keyFile" ${toString keyBits}
          chmod 0600 "$keyFile"
        fi

        if [ -f "$csrFile" ]; then
          exit 0
        fi

        openssl req \
          -new \
          -key "$keyFile" \
          "''${passInArgs[@]}" \
          -sha256 \
          -subj "$subject" \
          -out "$csrFile"
        chmod 0644 "$csrFile"
      '';
    })

    (writeShellApplication {
      name = "pd-openvpn-intermediate-ca-import-chain";
      runtimeInputs = [
        coreutils
        openssl
      ];
      text = commonScript + ''
        if [ "$#" -ne 2 ]; then
          echo "Usage: pd-openvpn-intermediate-ca-import-chain <root-cert-path> <intermediate-cert-path>" >&2
          exit 64
        fi

        ensure_layout

        rootSource="$1"
        intermediateSource="$2"

        if [ ! -f "$rootSource" ]; then
          echo "Root certificate not found: $rootSource" >&2
          exit 1
        fi

        if [ ! -f "$intermediateSource" ]; then
          echo "Intermediate certificate not found: $intermediateSource" >&2
          exit 1
        fi

        install -m 0644 "$rootSource" "$rootCertificateFile"
        install -m 0644 "$intermediateSource" "$certificateFile"
        openssl verify -CAfile "$rootCertificateFile" "$certificateFile"
        cat "$certificateFile" "$rootCertificateFile" > "$chainFile"
        chmod 0644 "$chainFile"
      '';
    })

    (writeShellApplication {
      name = "pd-openvpn-intermediate-ca-sign-server";
      runtimeInputs = [
        coreutils
        openssl
      ];
      text = commonScript + ''
        if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
          echo "Usage: pd-openvpn-intermediate-ca-sign-server <csr-path> [output-cert-path]" >&2
          exit 64
        fi

        ensure_layout
        ensure_signing_ready
        setup_passphrase_args

        csrPath="$1"
        outputPath="''${2:-$(default_output_path "$csrPath" "$issuedServerDir")}"

        if [ ! -f "$csrPath" ]; then
          echo "CSR not found: $csrPath" >&2
          exit 1
        fi

        install -d -m 0755 "$(dirname "$outputPath")"
        openssl ca \
          -batch \
          -config "$opensslConfig" \
          "''${passInArgs[@]}" \
          -extensions server_cert \
          -in "$csrPath" \
          -out "$outputPath"
        chmod 0644 "$outputPath"
      '';
    })

    (writeShellApplication {
      name = "pd-openvpn-intermediate-ca-sign-client";
      runtimeInputs = [
        coreutils
        openssl
      ];
      text = commonScript + ''
        if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
          echo "Usage: pd-openvpn-intermediate-ca-sign-client <csr-path> [output-cert-path]" >&2
          exit 64
        fi

        ensure_layout
        ensure_signing_ready
        setup_passphrase_args

        csrPath="$1"
        outputPath="''${2:-$(default_output_path "$csrPath" "$issuedClientDir")}"

        if [ ! -f "$csrPath" ]; then
          echo "CSR not found: $csrPath" >&2
          exit 1
        fi

        install -d -m 0755 "$(dirname "$outputPath")"
        openssl ca \
          -batch \
          -config "$opensslConfig" \
          "''${passInArgs[@]}" \
          -extensions client_cert \
          -in "$csrPath" \
          -out "$outputPath"
        chmod 0644 "$outputPath"
      '';
    })

    (writeShellApplication {
      name = "pd-openvpn-intermediate-ca-paths";
      runtimeInputs = [ coreutils ];
      text = commonScript + ''
        printf 'private-key=%s\n' "$keyFile"
        printf 'csr=%s\n' "$csrFile"
        printf 'certificate=%s\n' "$certificateFile"
        printf 'root-certificate=%s\n' "$rootCertificateFile"
        printf 'chain=%s\n' "$chainFile"
        printf 'incoming-csrs=%s\n' "$incomingDir"
        printf 'issued-server-certificates=%s\n' "$issuedServerDir"
        printf 'issued-client-certificates=%s\n' "$issuedClientDir"
      '';
    })
  ];
}
