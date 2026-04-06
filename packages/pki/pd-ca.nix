{
  writeShellApplication,
  coreutils,
  openssl,
}:
writeShellApplication {
  name = "pd-ca";
  runtimeInputs = [
    coreutils
    openssl
  ];
  text = ''
    readonly EX_USAGE=64
    readonly EX_NOINPUT=66
    readonly EX_CANTCREAT=73

    usage() {
      cat <<'EOF' >&2
Usage:
  pd-ca init-root OUT_DIR COMMON_NAME
  pd-ca issue-intermediate PARENT_CA_DIR COMMON_NAME OUT_DIR
  pd-ca issue-leaf CA_DIR PROFILE NAME COMMON_NAME OUT_DIR

  pd-ca init-workspace WORKSPACE_DIR
  pd-ca init-root-ca WORKSPACE_DIR COMMON_NAME
  pd-ca init-intermediate-ca WORKSPACE_DIR COMMON_NAME
  pd-ca issue-openvpn-server WORKSPACE_DIR NAME COMMON_NAME
  pd-ca issue-openvpn-client WORKSPACE_DIR NAME COMMON_NAME
  pd-ca revoke-openvpn-server WORKSPACE_DIR NAME
  pd-ca revoke-openvpn-client WORKSPACE_DIR NAME
  pd-ca stage-openvpn-server WORKSPACE_DIR NAME OUT_DIR
  pd-ca stage-openvpn-client WORKSPACE_DIR NAME OUT_DIR
  pd-ca bundle-chain OUT_FILE CERT_FILE [CERT_FILE...]

Profiles:
  openvpn-server
  openvpn-client
EOF
    }

    fail() {
      echo "$*" >&2
      exit 1
    }

    require_file() {
      if [ ! -f "$1" ]; then
        echo "Missing required file: $1" >&2
        exit "$EX_NOINPUT"
      fi
    }

    ensure_absent() {
      if [ -e "$1" ]; then
        echo "Refusing to overwrite existing path: $1" >&2
        exit "$EX_CANTCREAT"
      fi
    }

    workspace_root_ca_dir() {
      printf '%s/authorities/root\n' "$1"
    }

    workspace_intermediate_ca_dir() {
      printf '%s/authorities/intermediate\n' "$1"
    }

    workspace_openvpn_server_dir() {
      printf '%s/issued/openvpn/servers/%s\n' "$1" "$2"
    }

    workspace_openvpn_client_dir() {
      printf '%s/issued/openvpn/clients/%s\n' "$1" "$2"
    }

    copy_if_present() {
      local source_file="$1"
      local output_file="$2"

      if [ -f "$source_file" ]; then
        cp "$source_file" "$output_file"
      fi
    }

    init_ca_state() {
      local ca_dir="$1"
      local role="$2"
      local common_name="$3"

      mkdir -p "$ca_dir/issued/certs"
      mkdir -p "$ca_dir/revoked/certs"
      : > "$ca_dir/index.txt"
      printf 'unique_subject = no\n' > "$ca_dir/index.txt.attr"
      printf '00000001\n' > "$ca_dir/serial"
      printf '00000001\n' > "$ca_dir/crlnumber"
      printf 'serial\tlabel\tprofile\tnot_after\tsubject\n' > "$ca_dir/issued/records.tsv"
      printf 'serial\tlabel\tprofile\trevoked_at\tsubject\n' > "$ca_dir/revoked/records.tsv"
      printf '%s\n' "$role" > "$ca_dir/role"
      printf '%s\n' "$common_name" > "$ca_dir/common-name"
    }

    openssl_asn1_time_from_cert() {
      local cert_file="$1"
      local end_date

      end_date="$(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2-)"
      date -u -d "$end_date" '+%y%m%d%H%M%SZ'
    }

    openssl_revocation_time_now() {
      date -u '+%y%m%d%H%M%SZ'
    }

    write_ca_config() {
      local ca_dir="$1"
      local config_file="$2"

      cat > "$config_file" <<EOF
[ca]
default_ca = pd_ca

[pd_ca]
database = $ca_dir/index.txt
new_certs_dir = $ca_dir/issued/certs
certificate = $ca_dir/ca.crt
private_key = $ca_dir/ca.key
serial = $ca_dir/serial
crlnumber = $ca_dir/crlnumber
default_md = sha256
default_days = 3650
default_crl_days = 30
policy = policy_any
email_in_dn = no
copy_extensions = none
unique_subject = no
x509_extensions = usr_cert

[policy_any]
commonName = supplied
EOF
    }

    bundle_chain() {
      local out_file="$1"

      shift

      if [ "$#" -lt 1 ]; then
        echo "bundle-chain requires at least one certificate file." >&2
        exit "$EX_USAGE"
      fi

      cat "$@" > "$out_file"
    }

    refresh_ca_chain() {
      local ca_dir="$1"

      if [ -f "$ca_dir/issuer-chain.crt" ]; then
        bundle_chain "$ca_dir/ca-chain.crt" "$ca_dir/ca.crt" "$ca_dir/issuer-chain.crt"
      else
        bundle_chain "$ca_dir/ca-chain.crt" "$ca_dir/ca.crt"
      fi
    }

    refresh_crl() {
      local ca_dir="$1"
      local tmp_dir
      local config_file

      require_file "$ca_dir/ca.crt"
      require_file "$ca_dir/ca.key"
      require_file "$ca_dir/index.txt"
      require_file "$ca_dir/serial"
      require_file "$ca_dir/crlnumber"

      tmp_dir="$(mktemp -d)"
      config_file="$tmp_dir/ca.cnf"
      write_ca_config "$ca_dir" "$config_file"

      openssl ca \
        -config "$config_file" \
        -gencrl \
        -out "$ca_dir/ca.crl.pem" \
        >/dev/null 2>&1

      rm -rf "$tmp_dir"
    }

    record_issued_cert() {
      local ca_dir="$1"
      local serial="$2"
      local label="$3"
      local profile="$4"
      local common_name="$5"
      local subject
      local not_after
      local cert_file="$6"

      subject="/CN=$common_name"
      not_after="$(openssl_asn1_time_from_cert "$cert_file")"

      cp "$cert_file" "$ca_dir/issued/certs/$serial-$label.crt"
      printf 'V\t%s\t\t%s\tunknown\t%s\n' "$not_after" "$serial" "$subject" >> "$ca_dir/index.txt"
      printf '%s\t%s\t%s\t%s\t%s\n' "$serial" "$label" "$profile" "$not_after" "$subject" >> "$ca_dir/issued/records.tsv"
    }

    record_revoked_cert() {
      local ca_dir="$1"
      local serial="$2"
      local label="$3"
      local profile="$4"
      local common_name="$5"
      local revoked_at
      local subject
      local cert_file="$6"

      revoked_at="$(openssl_revocation_time_now)"
      subject="/CN=$common_name"

      cp "$cert_file" "$ca_dir/revoked/certs/$serial-$label.crt"
      printf '%s\t%s\t%s\t%s\t%s\n' "$serial" "$label" "$profile" "$revoked_at" "$subject" >> "$ca_dir/revoked/records.tsv"
    }

    refresh_workspace_bundles() {
      local workspace="$1"
      local root_ca_dir
      local intermediate_ca_dir

      root_ca_dir="$(workspace_root_ca_dir "$workspace")"
      intermediate_ca_dir="$(workspace_intermediate_ca_dir "$workspace")"

      mkdir -p "$workspace/bundles"

      if [ -f "$root_ca_dir/ca.crt" ]; then
        cp "$root_ca_dir/ca.crt" "$workspace/bundles/root-ca.crt"
      fi

      if [ -f "$intermediate_ca_dir/ca.crt" ]; then
        cp "$intermediate_ca_dir/ca.crt" "$workspace/bundles/intermediate-ca.crt"
      fi

      if [ -f "$intermediate_ca_dir/ca-chain.crt" ]; then
        cp "$intermediate_ca_dir/ca-chain.crt" "$workspace/bundles/openvpn-ca.crt"
      elif [ -f "$root_ca_dir/ca-chain.crt" ]; then
        cp "$root_ca_dir/ca-chain.crt" "$workspace/bundles/openvpn-ca.crt"
      fi

      if [ -f "$intermediate_ca_dir/ca.crl.pem" ]; then
        cp "$intermediate_ca_dir/ca.crl.pem" "$workspace/bundles/openvpn-ca.crl.pem"
      elif [ -f "$root_ca_dir/ca.crl.pem" ]; then
        cp "$root_ca_dir/ca.crl.pem" "$workspace/bundles/openvpn-ca.crl.pem"
      fi
    }

    stage_workspace_bundles() {
      local workspace="$1"
      local out_dir="$2"

      mkdir -p "$out_dir/bundles"

      copy_if_present "$workspace/bundles/root-ca.crt" "$out_dir/bundles/root-ca.crt"
      copy_if_present "$workspace/bundles/intermediate-ca.crt" "$out_dir/bundles/intermediate-ca.crt"
      copy_if_present "$workspace/bundles/openvpn-ca.crt" "$out_dir/bundles/openvpn-ca.crt"
      copy_if_present "$workspace/bundles/openvpn-ca.crl.pem" "$out_dir/bundles/openvpn-ca.crl.pem"
    }

    stage_identity_dir() {
      local source_dir="$1"
      local name="$2"
      local out_dir="$3"

      require_file "$source_dir/$name.crt"
      require_file "$source_dir/$name.key"
      require_file "$source_dir/ca-chain.crt"
      require_file "$source_dir/full-chain.crt"

      mkdir -p "$out_dir"

      cp "$source_dir/$name.crt" "$out_dir/$name.crt"
      cp "$source_dir/$name.key" "$out_dir/$name.key"
      cp "$source_dir/ca-chain.crt" "$out_dir/ca-chain.crt"
      cp "$source_dir/full-chain.crt" "$out_dir/full-chain.crt"
    }

    init_root() {
      local out_dir="$1"
      local common_name="$2"
      local tmp_dir
      local req_config

      ensure_absent "$out_dir/ca.key"
      ensure_absent "$out_dir/ca.crt"

      mkdir -p "$out_dir"

      tmp_dir="$(mktemp -d)"
      req_config="$tmp_dir/ca.cnf"

      cat > "$req_config" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3_ca
prompt = no

[dn]
CN = $common_name

[v3_ca]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
EOF

      openssl req \
        -x509 \
        -newkey rsa:2048 \
        -sha256 \
        -days 3650 \
        -nodes \
        -config "$req_config" \
        -keyout "$out_dir/ca.key" \
        -out "$out_dir/ca.crt" \
        >/dev/null 2>&1

      init_ca_state "$out_dir" "root" "$common_name"
      refresh_ca_chain "$out_dir"
      refresh_crl "$out_dir"

      rm -rf "$tmp_dir"
    }

    issue_intermediate() {
      local parent_ca_dir="$1"
      local common_name="$2"
      local out_dir="$3"
      local serial
      local tmp_dir
      local req_config
      local ext_config

      require_file "$parent_ca_dir/ca.crt"
      require_file "$parent_ca_dir/ca.key"
      require_file "$parent_ca_dir/serial"
      require_file "$parent_ca_dir/ca-chain.crt"

      ensure_absent "$out_dir/ca.key"
      ensure_absent "$out_dir/ca.crt"

      mkdir -p "$out_dir"

      serial="$(cat "$parent_ca_dir/serial")"
      tmp_dir="$(mktemp -d)"
      req_config="$tmp_dir/intermediate.cnf"
      ext_config="$tmp_dir/intermediate.ext"

      cat > "$req_config" <<EOF
[req]
distinguished_name = dn
prompt = no

[dn]
CN = $common_name
EOF

      openssl req \
        -new \
        -newkey rsa:2048 \
        -nodes \
        -config "$req_config" \
        -keyout "$out_dir/ca.key" \
        -out "$out_dir/ca.csr" \
        >/dev/null 2>&1

      cat > "$ext_config" <<EOF
basicConstraints=critical,CA:TRUE,pathlen:0
keyUsage=critical,keyCertSign,cRLSign
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EOF

      openssl x509 \
        -req \
        -sha256 \
        -days 3650 \
        -in "$out_dir/ca.csr" \
        -CA "$parent_ca_dir/ca.crt" \
        -CAkey "$parent_ca_dir/ca.key" \
        -CAserial "$parent_ca_dir/serial" \
        -out "$out_dir/ca.crt" \
        -extfile "$ext_config" \
        >/dev/null 2>&1

      init_ca_state "$out_dir" "intermediate" "$common_name"
      cp "$parent_ca_dir/ca-chain.crt" "$out_dir/issuer-chain.crt"
      refresh_ca_chain "$out_dir"
      refresh_crl "$out_dir"
      record_issued_cert "$parent_ca_dir" "$serial" "$(basename "$out_dir")" "intermediate" "$common_name" "$out_dir/ca.crt"

      rm -rf "$tmp_dir"
      rm -f "$out_dir/ca.csr"
    }

    issue_leaf() {
      local ca_dir="$1"
      local profile="$2"
      local name="$3"
      local common_name="$4"
      local out_dir="$5"
      local serial
      local extended_key_usage
      local tmp_dir
      local req_config
      local ext_config

      require_file "$ca_dir/ca.crt"
      require_file "$ca_dir/ca.key"
      require_file "$ca_dir/serial"
      require_file "$ca_dir/ca-chain.crt"

      case "$profile" in
        openvpn-server)
          extended_key_usage="serverAuth"
          ;;
        openvpn-client)
          extended_key_usage="clientAuth"
          ;;
        *)
          echo "Unsupported certificate profile: $profile" >&2
          usage
          exit "$EX_USAGE"
          ;;
      esac

      ensure_absent "$out_dir/$name.key"
      ensure_absent "$out_dir/$name.crt"

      mkdir -p "$out_dir"

      serial="$(cat "$ca_dir/serial")"
      tmp_dir="$(mktemp -d)"
      req_config="$tmp_dir/$name.cnf"
      ext_config="$tmp_dir/$name.ext"

      cat > "$req_config" <<EOF
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
        -config "$req_config" \
        -keyout "$out_dir/$name.key" \
        -out "$out_dir/$name.csr" \
        >/dev/null 2>&1

      cat > "$ext_config" <<EOF
basicConstraints=CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=$extended_key_usage
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EOF

      openssl x509 \
        -req \
        -sha256 \
        -days 3650 \
        -in "$out_dir/$name.csr" \
        -CA "$ca_dir/ca.crt" \
        -CAkey "$ca_dir/ca.key" \
        -CAserial "$ca_dir/serial" \
        -out "$out_dir/$name.crt" \
        -extfile "$ext_config" \
        >/dev/null 2>&1

      cp "$ca_dir/ca-chain.crt" "$out_dir/ca-chain.crt"
      bundle_chain "$out_dir/full-chain.crt" "$out_dir/$name.crt" "$out_dir/ca-chain.crt"
      record_issued_cert "$ca_dir" "$serial" "$name" "$profile" "$common_name" "$out_dir/$name.crt"

      rm -rf "$tmp_dir"
      rm -f "$out_dir/$name.csr"
    }

    init_workspace() {
      local workspace="$1"

      mkdir -p \
        "$workspace/authorities" \
        "$workspace/issued/openvpn/servers" \
        "$workspace/issued/openvpn/clients" \
        "$workspace/bundles"
    }

    init_root_ca() {
      local workspace="$1"
      local common_name="$2"
      local root_ca_dir

      init_workspace "$workspace"
      root_ca_dir="$(workspace_root_ca_dir "$workspace")"
      init_root "$root_ca_dir" "$common_name"
      refresh_workspace_bundles "$workspace"
    }

    init_intermediate_ca() {
      local workspace="$1"
      local common_name="$2"
      local root_ca_dir
      local intermediate_ca_dir

      init_workspace "$workspace"
      root_ca_dir="$(workspace_root_ca_dir "$workspace")"
      intermediate_ca_dir="$(workspace_intermediate_ca_dir "$workspace")"

      issue_intermediate "$root_ca_dir" "$common_name" "$intermediate_ca_dir"
      refresh_workspace_bundles "$workspace"
    }

    issue_openvpn_server() {
      local workspace="$1"
      local name="$2"
      local common_name="$3"
      local intermediate_ca_dir
      local out_dir

      init_workspace "$workspace"
      intermediate_ca_dir="$(workspace_intermediate_ca_dir "$workspace")"
      out_dir="$(workspace_openvpn_server_dir "$workspace" "$name")"

      issue_leaf "$intermediate_ca_dir" openvpn-server "$name" "$common_name" "$out_dir"
      refresh_workspace_bundles "$workspace"
    }

    issue_openvpn_client() {
      local workspace="$1"
      local name="$2"
      local common_name="$3"
      local intermediate_ca_dir
      local out_dir

      init_workspace "$workspace"
      intermediate_ca_dir="$(workspace_intermediate_ca_dir "$workspace")"
      out_dir="$(workspace_openvpn_client_dir "$workspace" "$name")"

      issue_leaf "$intermediate_ca_dir" openvpn-client "$name" "$common_name" "$out_dir"
      refresh_workspace_bundles "$workspace"
    }

    revoke_cert() {
      local ca_dir="$1"
      local cert_file="$2"
      local label="$3"
      local profile="$4"
      local common_name="$5"
      local serial
      local tmp_dir
      local config_file

      require_file "$cert_file"
      require_file "$ca_dir/index.txt"

      serial="$(openssl x509 -in "$cert_file" -noout -serial | cut -d= -f2)"
      tmp_dir="$(mktemp -d)"
      config_file="$tmp_dir/ca.cnf"
      write_ca_config "$ca_dir" "$config_file"

      openssl ca \
        -config "$config_file" \
        -revoke "$cert_file" \
        >/dev/null 2>&1

      refresh_crl "$ca_dir"
      record_revoked_cert "$ca_dir" "$serial" "$label" "$profile" "$common_name" "$cert_file"

      rm -rf "$tmp_dir"
    }

    revoke_openvpn_server() {
      local workspace="$1"
      local name="$2"
      local intermediate_ca_dir
      local cert_dir

      intermediate_ca_dir="$(workspace_intermediate_ca_dir "$workspace")"
      cert_dir="$(workspace_openvpn_server_dir "$workspace" "$name")"

      revoke_cert "$intermediate_ca_dir" "$cert_dir/$name.crt" "$name" "openvpn-server" "$name"
      refresh_workspace_bundles "$workspace"
    }

    revoke_openvpn_client() {
      local workspace="$1"
      local name="$2"
      local intermediate_ca_dir
      local cert_dir

      intermediate_ca_dir="$(workspace_intermediate_ca_dir "$workspace")"
      cert_dir="$(workspace_openvpn_client_dir "$workspace" "$name")"

      revoke_cert "$intermediate_ca_dir" "$cert_dir/$name.crt" "$name" "openvpn-client" "$name"
      refresh_workspace_bundles "$workspace"
    }

    stage_openvpn_server() {
      local workspace="$1"
      local name="$2"
      local out_dir="$3"
      local cert_dir
      local staged_identity_dir

      cert_dir="$(workspace_openvpn_server_dir "$workspace" "$name")"
      staged_identity_dir="$out_dir/issued/openvpn/servers/$name"

      ensure_absent "$out_dir"
      mkdir -p "$out_dir"

      stage_workspace_bundles "$workspace" "$out_dir"
      stage_identity_dir "$cert_dir" "$name" "$staged_identity_dir"
    }

    stage_openvpn_client() {
      local workspace="$1"
      local name="$2"
      local out_dir="$3"
      local cert_dir
      local staged_identity_dir

      cert_dir="$(workspace_openvpn_client_dir "$workspace" "$name")"
      staged_identity_dir="$out_dir/issued/openvpn/clients/$name"

      ensure_absent "$out_dir"
      mkdir -p "$out_dir"

      stage_workspace_bundles "$workspace" "$out_dir"
      stage_identity_dir "$cert_dir" "$name" "$staged_identity_dir"
    }

    if [ "$#" -lt 1 ]; then
      usage
      exit "$EX_USAGE"
    fi

    case "$1" in
      init-root)
        if [ "$#" -ne 3 ]; then
          usage
          exit "$EX_USAGE"
        fi

        init_root "$2" "$3"
        ;;
      issue-intermediate)
        if [ "$#" -ne 4 ]; then
          usage
          exit "$EX_USAGE"
        fi

        issue_intermediate "$2" "$3" "$4"
        ;;
      issue-leaf)
        if [ "$#" -ne 6 ]; then
          usage
          exit "$EX_USAGE"
        fi

        issue_leaf "$2" "$3" "$4" "$5" "$6"
        ;;
      init-workspace)
        if [ "$#" -ne 2 ]; then
          usage
          exit "$EX_USAGE"
        fi

        init_workspace "$2"
        ;;
      init-root-ca)
        if [ "$#" -ne 3 ]; then
          usage
          exit "$EX_USAGE"
        fi

        init_root_ca "$2" "$3"
        ;;
      init-intermediate-ca)
        if [ "$#" -ne 3 ]; then
          usage
          exit "$EX_USAGE"
        fi

        init_intermediate_ca "$2" "$3"
        ;;
      issue-openvpn-server)
        if [ "$#" -ne 4 ]; then
          usage
          exit "$EX_USAGE"
        fi

        issue_openvpn_server "$2" "$3" "$4"
        ;;
      issue-openvpn-client)
        if [ "$#" -ne 4 ]; then
          usage
          exit "$EX_USAGE"
        fi

        issue_openvpn_client "$2" "$3" "$4"
        ;;
      revoke-openvpn-server)
        if [ "$#" -ne 3 ]; then
          usage
          exit "$EX_USAGE"
        fi

        revoke_openvpn_server "$2" "$3"
        ;;
      revoke-openvpn-client)
        if [ "$#" -ne 3 ]; then
          usage
          exit "$EX_USAGE"
        fi

        revoke_openvpn_client "$2" "$3"
        ;;
      stage-openvpn-server)
        if [ "$#" -ne 4 ]; then
          usage
          exit "$EX_USAGE"
        fi

        stage_openvpn_server "$2" "$3" "$4"
        ;;
      stage-openvpn-client)
        if [ "$#" -ne 4 ]; then
          usage
          exit "$EX_USAGE"
        fi

        stage_openvpn_client "$2" "$3" "$4"
        ;;
      bundle-chain)
        if [ "$#" -lt 3 ]; then
          usage
          exit "$EX_USAGE"
        fi

        bundle_out_file="$2"
        shift 2
        bundle_chain "$bundle_out_file" "$@"
        ;;
      *)
        usage
        exit "$EX_USAGE"
        ;;
    esac
  '';

  meta = {
    description = "Certificate-authority helper for pseudo.design PKI workflows.";
  };
}
