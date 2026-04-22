{
  lib,
  coreutils,
  openssl,
  symlinkJoin,
  writeShellApplication,
  stateDir,
  identityName,
  subject,
  subjectAltNames ? [ ],
  passphraseFile ? null,
  keyBits ? 4096,
}:
let
  privateDir = "${stateDir}/private";
  csrDir = "${stateDir}/csr";
  certDir = "${stateDir}/certs";
  keyFile = "${privateDir}/${identityName}.key";
  csrFile = "${csrDir}/${identityName}.csr";
  certificateFile = "${certDir}/${identityName}.crt";
  chainFile = "${certDir}/ca-chain.crt";
  fullChainFile = "${certDir}/${identityName}-fullchain.crt";
  sanList = lib.concatStringsSep "," subjectAltNames;

  commonScript = ''
    set -euo pipefail

    readonly stateDir=${lib.escapeShellArg stateDir}
    readonly privateDir=${lib.escapeShellArg privateDir}
    readonly csrDir=${lib.escapeShellArg csrDir}
    readonly certDir=${lib.escapeShellArg certDir}
    readonly keyFile=${lib.escapeShellArg keyFile}
    readonly csrFile=${lib.escapeShellArg csrFile}
    readonly certificateFile=${lib.escapeShellArg certificateFile}
    readonly chainFile=${lib.escapeShellArg chainFile}
    readonly fullChainFile=${lib.escapeShellArg fullChainFile}
    readonly subject=${lib.escapeShellArg subject}
    readonly sanList=${lib.escapeShellArg sanList}
    readonly passphraseFile=${lib.escapeShellArg (if passphraseFile == null then "" else passphraseFile)}

    declare -a passInArgs=()
    declare -a passOutArgs=()

    : \
      "$stateDir" \
      "$privateDir" \
      "$csrDir" \
      "$certDir" \
      "$keyFile" \
      "$csrFile" \
      "$certificateFile" \
      "$chainFile" \
      "$fullChainFile" \
      "$subject" \
      "$sanList" \
      "$passphraseFile" \
      "''${passInArgs[*]-}" \
      "''${passOutArgs[*]-}"

    ensure_layout() {
      install -d -m 0700 "$stateDir" "$privateDir"
      install -d -m 0755 "$csrDir" "$certDir"
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
  '';
in
symlinkJoin {
  name = "pd-openvpn-leaf-tools";
  paths = [
    (writeShellApplication {
      name = "pd-openvpn-leaf-init";
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

        declare -a addExtArgs=()
        if [ -n "$sanList" ]; then
          addExtArgs=(-addext "subjectAltName = $sanList")
        fi

        openssl req \
          -new \
          -key "$keyFile" \
          "''${passInArgs[@]}" \
          -sha256 \
          -subj "$subject" \
          "''${addExtArgs[@]}" \
          -out "$csrFile"
        chmod 0644 "$csrFile"
      '';
    })

    (writeShellApplication {
      name = "pd-openvpn-leaf-import-certificate";
      runtimeInputs = [
        coreutils
        openssl
      ];
      text = commonScript + ''
        if [ "$#" -ne 2 ]; then
          echo "Usage: pd-openvpn-leaf-import-certificate <certificate-path> <chain-path>" >&2
          exit 64
        fi

        ensure_layout

        certificateSource="$1"
        chainSource="$2"

        if [ ! -f "$certificateSource" ]; then
          echo "Certificate not found: $certificateSource" >&2
          exit 1
        fi

        if [ ! -f "$chainSource" ]; then
          echo "CA chain not found: $chainSource" >&2
          exit 1
        fi

        install -m 0644 "$certificateSource" "$certificateFile"
        install -m 0644 "$chainSource" "$chainFile"
        cat "$certificateFile" "$chainFile" > "$fullChainFile"
        chmod 0644 "$fullChainFile"
      '';
    })

    (writeShellApplication {
      name = "pd-openvpn-leaf-verify";
      runtimeInputs = [
        coreutils
        openssl
      ];
      text = commonScript + ''
        if [ "$#" -ne 1 ]; then
          echo "Usage: pd-openvpn-leaf-verify <server|client>" >&2
          exit 64
        fi

        if [ ! -f "$certificateFile" ] || [ ! -f "$chainFile" ]; then
          echo "Leaf certificate or CA chain is missing. Import them first." >&2
          exit 1
        fi

        purpose="$1"
        case "$purpose" in
          server)
            openssl verify -purpose sslserver -CAfile "$chainFile" "$certificateFile"
            ;;
          client)
            openssl verify -purpose sslclient -CAfile "$chainFile" "$certificateFile"
            ;;
          *)
            echo "Usage: pd-openvpn-leaf-verify <server|client>" >&2
            exit 64
            ;;
        esac
      '';
    })

    (writeShellApplication {
      name = "pd-openvpn-leaf-paths";
      runtimeInputs = [ coreutils ];
      text = commonScript + ''
        printf 'private-key=%s\n' "$keyFile"
        printf 'csr=%s\n' "$csrFile"
        printf 'certificate=%s\n' "$certificateFile"
        printf 'chain=%s\n' "$chainFile"
        printf 'full-chain=%s\n' "$fullChainFile"
      '';
    })
  ];
}
