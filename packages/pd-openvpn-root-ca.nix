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
  certificateDays ? 7300,
  intermediateDays ? 3650,
  pathLen ? 1,
}:
let
  privateDir = "${stateDir}/private";
  certDir = "${stateDir}/certs";
  incomingDir = "${stateDir}/incoming/intermediates";
  issuedDir = "${stateDir}/issued/intermediates";
  newCertsDir = "${stateDir}/newcerts";
  databaseFile = "${stateDir}/index.txt";
  serialFile = "${stateDir}/serial";
  keyFile = "${privateDir}/root-ca.key";
  certificateFile = "${certDir}/root-ca.crt";

  opensslConfig = writeText "pd-openvpn-root-ca.cnf" ''
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
    default_days = ${toString intermediateDays}
    policy = policy_loose
    email_in_dn = no
    copy_extensions = none
    unique_subject = no

    [ policy_loose ]
    commonName = supplied
    countryName = optional
    stateOrProvinceName = optional
    localityName = optional
    organizationName = optional
    organizationalUnitName = optional
    emailAddress = optional

    [ v3_ca ]
    subjectKeyIdentifier = hash
    authorityKeyIdentifier = keyid:always
    basicConstraints = critical,CA:true,pathlen:${toString pathLen}
    keyUsage = critical,keyCertSign,cRLSign

    [ v3_intermediate_ca ]
    subjectKeyIdentifier = hash
    authorityKeyIdentifier = keyid:always,issuer
    basicConstraints = critical,CA:true,pathlen:0
    keyUsage = critical,keyCertSign,cRLSign
  '';

  commonScript = ''
    set -euo pipefail

    readonly stateDir=${lib.escapeShellArg stateDir}
    readonly privateDir=${lib.escapeShellArg privateDir}
    readonly certDir=${lib.escapeShellArg certDir}
    readonly incomingDir=${lib.escapeShellArg incomingDir}
    readonly issuedDir=${lib.escapeShellArg issuedDir}
    readonly newCertsDir=${lib.escapeShellArg newCertsDir}
    readonly databaseFile=${lib.escapeShellArg databaseFile}
    readonly serialFile=${lib.escapeShellArg serialFile}
    readonly keyFile=${lib.escapeShellArg keyFile}
    readonly certificateFile=${lib.escapeShellArg certificateFile}
    readonly opensslConfig=${lib.escapeShellArg opensslConfig}
    readonly subject=${lib.escapeShellArg subject}
    readonly passphraseFile=${lib.escapeShellArg (if passphraseFile == null then "" else passphraseFile)}

    declare -a passInArgs=()
    declare -a passOutArgs=()

    : \
      "$stateDir" \
      "$privateDir" \
      "$certDir" \
      "$incomingDir" \
      "$issuedDir" \
      "$newCertsDir" \
      "$databaseFile" \
      "$serialFile" \
      "$keyFile" \
      "$certificateFile" \
      "$opensslConfig" \
      "$subject" \
      "$passphraseFile" \
      "''${passInArgs[*]-}" \
      "''${passOutArgs[*]-}"

    ensure_layout() {
      install -d -m 0700 "$stateDir" "$privateDir"
      install -d -m 0755 "$certDir" "$newCertsDir" "$incomingDir" "$issuedDir"
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

    ensure_initialized() {
      if [ ! -f "$keyFile" ] || [ ! -f "$certificateFile" ]; then
        echo "Root CA is not initialized. Run pd-openvpn-root-ca-init first." >&2
        exit 1
      fi
    }

    default_output_path() {
      local csrPath="$1"
      local baseName

      baseName="$(basename "$csrPath")"
      baseName="''${baseName%.csr}"
      printf '%s/%s.crt\n' "$issuedDir" "$baseName"
    }
  '';
in
symlinkJoin {
  name = "pd-openvpn-root-ca-tools";
  paths = [
    (writeShellApplication {
      name = "pd-openvpn-root-ca-init";
      runtimeInputs = [
        coreutils
        openssl
      ];
      text = commonScript + ''
        ensure_layout
        setup_passphrase_args

        if [ -f "$keyFile" ] && [ -f "$certificateFile" ]; then
          exit 0
        fi

        if [ -f "$keyFile" ] || [ -f "$certificateFile" ]; then
          echo "Root CA exists in a partial state. Refusing to overwrite it." >&2
          exit 1
        fi

        umask 077
        openssl genrsa "''${passOutArgs[@]}" -out "$keyFile" ${toString keyBits}
        openssl req \
          -x509 \
          -new \
          -key "$keyFile" \
          "''${passInArgs[@]}" \
          -sha256 \
          -days ${toString certificateDays} \
          -subj "$subject" \
          -extensions v3_ca \
          -config "$opensslConfig" \
          -out "$certificateFile"

        chmod 0600 "$keyFile"
        chmod 0644 "$certificateFile"
      '';
    })

    (writeShellApplication {
      name = "pd-openvpn-root-ca-sign-intermediate";
      runtimeInputs = [
        coreutils
        openssl
      ];
      text = commonScript + ''
        if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
          echo "Usage: pd-openvpn-root-ca-sign-intermediate <csr-path> [output-cert-path]" >&2
          exit 64
        fi

        ensure_layout
        ensure_initialized
        setup_passphrase_args

        csrPath="$1"
        outputPath="''${2:-$(default_output_path "$csrPath")}"

        if [ ! -f "$csrPath" ]; then
          echo "CSR not found: $csrPath" >&2
          exit 1
        fi

        install -d -m 0755 "$(dirname "$outputPath")"
        openssl ca \
          -batch \
          -config "$opensslConfig" \
          "''${passInArgs[@]}" \
          -extensions v3_intermediate_ca \
          -in "$csrPath" \
          -out "$outputPath"
        chmod 0644 "$outputPath"
      '';
    })

    (writeShellApplication {
      name = "pd-openvpn-root-ca-paths";
      runtimeInputs = [ coreutils ];
      text = commonScript + ''
        printf 'private-key=%s\n' "$keyFile"
        printf 'certificate=%s\n' "$certificateFile"
        printf 'incoming-csrs=%s\n' "$incomingDir"
        printf 'issued-certificates=%s\n' "$issuedDir"
      '';
    })
  ];
}
