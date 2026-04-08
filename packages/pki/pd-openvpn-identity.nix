{
  writeShellApplication,
  coreutils,
  gnused,
  openssl,
}:
writeShellApplication {
  name = "pd-openvpn-identity";
  runtimeInputs = [
    coreutils
    gnused
    openssl
  ];
  text = ''
    readonly EX_USAGE=64
    readonly EX_DATAERR=65
    readonly EX_NOINPUT=66
    readonly EX_CANTCREAT=73

    usage() {
      cat <<'EOF' >&2
Usage:
  pd-openvpn-identity init-server IDENTITY_DIR NAME COMMON_NAME
  pd-openvpn-identity init-client IDENTITY_DIR NAME COMMON_NAME
  pd-openvpn-identity prepare-server-rekey IDENTITY_DIR NAME COMMON_NAME
  pd-openvpn-identity prepare-client-rekey IDENTITY_DIR NAME COMMON_NAME
  pd-openvpn-identity activate-pending IDENTITY_DIR REQUEST_ID CERT_DIR
  pd-openvpn-identity import-active IDENTITY_DIR KEY_FILE CERT_DIR
  pd-openvpn-identity show IDENTITY_DIR

Profiles:
  openvpn-server
  openvpn-client
EOF
    }

    fail() {
      echo "$1" >&2
      exit "''${2-1}"
    }

    require_file() {
      if [ ! -f "$1" ]; then
        fail "Missing required file: $1" "$EX_NOINPUT"
      fi
    }

    require_dir() {
      if [ ! -d "$1" ]; then
        fail "Missing required directory: $1" "$EX_NOINPUT"
      fi
    }

    ensure_absent() {
      if [ -e "$1" ]; then
        fail "Refusing to overwrite existing path: $1" "$EX_CANTCREAT"
      fi
    }

    request_config_extended_key_usage() {
      case "$1" in
        openvpn-server)
          printf '%s\n' "serverAuth"
          ;;
        openvpn-client)
          printf '%s\n' "clientAuth"
          ;;
        *)
          fail "Unsupported identity profile: $1" "$EX_USAGE"
          ;;
      esac
    }

    cert_serial() {
      openssl x509 -in "$1" -noout -serial | cut -d= -f2
    }

    cert_dir_name() {
      printf '%s\n' "''${1##*/}"
    }

    cert_dir_common_name() {
      local cert_dir="$1"
      local name

      name="$(cert_dir_name "$cert_dir")"

      if [ -f "$cert_dir/common-name" ]; then
        cat "$cert_dir/common-name"
      else
        openssl x509 \
          -in "$cert_dir/$name.crt" \
          -noout \
          -subject \
          -nameopt RFC2253 |
          sed \
            -e 's/^subject=//' \
            -e 's/.*CN=//' \
            -e 's/,.*$//'
      fi
    }

    cert_dir_profile() {
      require_file "$1/profile"
      cat "$1/profile"
    }

    identity_name() {
      require_file "$1/identity-name"
      cat "$1/identity-name"
    }

    identity_profile() {
      require_file "$1/profile"
      cat "$1/profile"
    }

    identity_common_name() {
      require_file "$1/common-name"
      cat "$1/common-name"
    }

    request_common_name() {
      require_file "$1/common-name"
      cat "$1/common-name"
    }

    request_profile() {
      require_file "$1/profile"
      cat "$1/profile"
    }

    request_key_file() {
      local identity_dir="$1"
      local request_id="$2"
      local name

      name="$(identity_name "$identity_dir")"
      printf '%s/pending/%s/%s.key\n' "$identity_dir" "$request_id" "$name"
    }

    cert_matches_key() {
      local key_file="$1"
      local cert_file="$2"
      local tmp_dir
      local cert_public_key
      local key_public_key
      local result

      tmp_dir="$(mktemp -d)"
      openssl x509 -in "$cert_file" -pubkey -noout > "$tmp_dir/cert.pub.pem"
      openssl pkey -in "$key_file" -pubout > "$tmp_dir/key.pub.pem"
      cert_public_key="$(cat "$tmp_dir/cert.pub.pem")"
      key_public_key="$(cat "$tmp_dir/key.pub.pem")"

      if [ "$cert_public_key" = "$key_public_key" ]; then
        result=0
      else
        result=1
      fi

      rm -rf "$tmp_dir"
      return "$result"
    }

    ensure_identity_metadata() {
      local identity_dir="$1"
      local name="$2"
      local common_name="$3"
      local profile="$4"

      mkdir -p "$identity_dir/pending" "$identity_dir/history"

      if [ -f "$identity_dir/identity-name" ]; then
        if [ "$(identity_name "$identity_dir")" != "$name" ]; then
          fail "Identity name mismatch for $identity_dir." "$EX_DATAERR"
        fi
      else
        printf '%s\n' "$name" > "$identity_dir/identity-name"
      fi

      if [ -f "$identity_dir/profile" ]; then
        if [ "$(identity_profile "$identity_dir")" != "$profile" ]; then
          fail "Identity profile mismatch for $identity_dir." "$EX_DATAERR"
        fi
      else
        printf '%s\n' "$profile" > "$identity_dir/profile"
      fi

      printf '%s\n' "$common_name" > "$identity_dir/common-name"
    }

    create_pending_request() {
      local identity_dir="$1"
      local request_id="$2"
      local name="$3"
      local common_name="$4"
      local profile="$5"
      local request_kind="$6"
      local request_dir
      local request_config
      local extended_key_usage

      request_dir="$identity_dir/pending/$request_id"
      ensure_absent "$request_dir"
      mkdir -p "$request_dir"

      extended_key_usage="$(request_config_extended_key_usage "$profile")"
      request_config="$(mktemp)"

      cat > "$request_config" <<EOF
[req]
distinguished_name = dn
req_extensions = v3_req
prompt = no

[dn]
CN = $common_name

[v3_req]
basicConstraints = CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = $extended_key_usage
subjectKeyIdentifier = hash
EOF

      openssl req \
        -new \
        -newkey rsa:2048 \
        -nodes \
        -config "$request_config" \
        -keyout "$request_dir/$name.key" \
        -out "$request_dir/$name.csr" \
        >/dev/null 2>&1

      rm -f "$request_config"

      printf '%s\n' "$common_name" > "$request_dir/common-name"
      printf '%s\n' "$profile" > "$request_dir/profile"
      printf '%s\n' "$request_kind" > "$request_dir/request-kind"
      date -u '+%Y%m%dT%H%M%SZ' > "$request_dir/created-at"

      printf '%s\n' "$request_dir"
    }

    archive_active_dir() {
      local identity_dir="$1"
      local name="$2"
      local active_dir
      local archive_dir
      local timestamp
      local serial

      active_dir="$identity_dir/active"

      if [ ! -d "$active_dir" ]; then
        return 0
      fi

      require_file "$active_dir/$name.key"
      require_file "$active_dir/$name.crt"

      timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
      serial="$(cert_serial "$active_dir/$name.crt")"
      archive_dir="$identity_dir/history/$timestamp-$serial"

      ensure_absent "$archive_dir"
      mv "$active_dir" "$archive_dir"
    }

    install_active_dir() {
      local identity_dir="$1"
      local key_file="$2"
      local cert_dir="$3"
      local request_id="$4"
      local name
      local common_name
      local profile
      local active_dir

      name="$(cert_dir_name "$cert_dir")"
      common_name="$(cert_dir_common_name "$cert_dir")"
      profile="$(cert_dir_profile "$cert_dir")"

      require_file "$key_file"
      require_file "$cert_dir/$name.crt"
      require_file "$cert_dir/ca-chain.crt"
      require_file "$cert_dir/full-chain.crt"

      if ! cert_matches_key "$key_file" "$cert_dir/$name.crt"; then
        fail "Private key does not match certificate: $key_file" "$EX_DATAERR"
      fi

      ensure_identity_metadata "$identity_dir" "$name" "$common_name" "$profile"
      archive_active_dir "$identity_dir" "$name"

      active_dir="$(mktemp -d "$identity_dir/.active.XXXXXX")"
      cp "$key_file" "$active_dir/$name.key"
      cp "$cert_dir/$name.crt" "$active_dir/$name.crt"
      cp "$cert_dir/ca-chain.crt" "$active_dir/ca-chain.crt"
      cp "$cert_dir/full-chain.crt" "$active_dir/full-chain.crt"
      printf '%s\n' "$common_name" > "$active_dir/common-name"
      printf '%s\n' "$profile" > "$active_dir/profile"
      printf '%s\n' "$request_id" > "$active_dir/installed-request-id"
      chmod -R u=rwX,go= "$active_dir"
      mv "$active_dir" "$identity_dir/active"

      printf '%s\n' "$identity_dir/active"
    }

    init_identity() {
      local identity_dir="$1"
      local name="$2"
      local common_name="$3"
      local profile="$4"

      ensure_absent "$identity_dir"
      ensure_identity_metadata "$identity_dir" "$name" "$common_name" "$profile"
      create_pending_request "$identity_dir" initial "$name" "$common_name" "$profile" issue
    }

    prepare_rekey() {
      local identity_dir="$1"
      local name="$2"
      local common_name="$3"
      local profile="$4"
      local request_id

      ensure_identity_metadata "$identity_dir" "$name" "$common_name" "$profile"
      request_id="$(date -u '+%Y%m%dT%H%M%SZ')"
      create_pending_request "$identity_dir" "$request_id" "$name" "$common_name" "$profile" rekey
    }

    activate_pending() {
      local identity_dir="$1"
      local request_id="$2"
      local cert_dir="$3"
      local request_dir
      local name
      local request_name
      local common_name
      local profile
      local cert_name

      request_dir="$identity_dir/pending/$request_id"
      require_dir "$request_dir"

      name="$(identity_name "$identity_dir")"
      request_name="$name"
      cert_name="$(cert_dir_name "$cert_dir")"
      common_name="$(request_common_name "$request_dir")"
      profile="$(request_profile "$request_dir")"

      if [ "$cert_name" != "$request_name" ]; then
        fail "Certificate directory name does not match identity name: $cert_dir" "$EX_DATAERR"
      fi

      if [ "$(cert_dir_common_name "$cert_dir")" != "$common_name" ]; then
        fail "Certificate common name does not match pending request." "$EX_DATAERR"
      fi

      if [ "$(cert_dir_profile "$cert_dir")" != "$profile" ]; then
        fail "Certificate profile does not match pending request." "$EX_DATAERR"
      fi

      install_active_dir "$identity_dir" "$(request_key_file "$identity_dir" "$request_id")" "$cert_dir" "$request_id"
      rm -rf "$request_dir"
    }

    import_active() {
      local identity_dir="$1"
      local key_file="$2"
      local cert_dir="$3"

      install_active_dir "$identity_dir" "$key_file" "$cert_dir" imported
    }

    show_identity() {
      local identity_dir="$1"
      local active_dir
      local request_dir

      require_dir "$identity_dir"

      printf 'identity-name: %s\n' "$(identity_name "$identity_dir")"
      printf 'profile: %s\n' "$(identity_profile "$identity_dir")"
      printf 'common-name: %s\n' "$(identity_common_name "$identity_dir")"

      active_dir="$identity_dir/active"
      if [ -d "$active_dir" ]; then
        printf 'active: yes\n'
        printf 'active-dir: %s\n' "$active_dir"
      else
        printf 'active: no\n'
      fi

      for request_dir in "$identity_dir"/pending/*; do
        [ -d "$request_dir" ] || continue
        printf 'pending: %s\n' "''${request_dir##*/}"
      done
    }

    if [ "$#" -lt 1 ]; then
      usage
      exit "$EX_USAGE"
    fi

    case "$1" in
      init-server)
        if [ "$#" -ne 4 ]; then
          usage
          exit "$EX_USAGE"
        fi

        init_identity "$2" "$3" "$4" openvpn-server
        ;;
      init-client)
        if [ "$#" -ne 4 ]; then
          usage
          exit "$EX_USAGE"
        fi

        init_identity "$2" "$3" "$4" openvpn-client
        ;;
      prepare-server-rekey)
        if [ "$#" -ne 4 ]; then
          usage
          exit "$EX_USAGE"
        fi

        prepare_rekey "$2" "$3" "$4" openvpn-server
        ;;
      prepare-client-rekey)
        if [ "$#" -ne 4 ]; then
          usage
          exit "$EX_USAGE"
        fi

        prepare_rekey "$2" "$3" "$4" openvpn-client
        ;;
      activate-pending)
        if [ "$#" -ne 4 ]; then
          usage
          exit "$EX_USAGE"
        fi

        activate_pending "$2" "$3" "$4"
        ;;
      import-active)
        if [ "$#" -ne 4 ]; then
          usage
          exit "$EX_USAGE"
        fi

        import_active "$2" "$3" "$4"
        ;;
      show)
        if [ "$#" -ne 2 ]; then
          usage
          exit "$EX_USAGE"
        fi

        show_identity "$2"
        ;;
      *)
        usage
        exit "$EX_USAGE"
        ;;
    esac
  '';

  meta = {
    description = "Manage endpoint-local OpenVPN identity state.";
  };
}
