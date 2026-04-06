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

    usage() {
      cat <<'EOF' >&2
Usage:
  pd-ca init-root OUT_DIR COMMON_NAME
  pd-ca issue-intermediate PARENT_CA_DIR COMMON_NAME OUT_DIR
  pd-ca issue-leaf CA_DIR PROFILE NAME COMMON_NAME OUT_DIR

Profiles:
  openvpn-server
  openvpn-client
EOF
    }

    init_root() {
      local out_dir="$1"
      local common_name="$2"
      local tmp_dir
      local req_config

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

      rm -rf "$tmp_dir"
    }

    issue_intermediate() {
      local parent_ca_dir="$1"
      local common_name="$2"
      local out_dir="$3"
      local tmp_dir
      local req_config
      local ext_config

      mkdir -p "$out_dir"

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
        -CAcreateserial \
        -out "$out_dir/ca.crt" \
        -extfile "$ext_config" \
        >/dev/null 2>&1

      rm -rf "$tmp_dir"
      rm -f "$out_dir/ca.csr"
    }

    issue_leaf() {
      local ca_dir="$1"
      local profile="$2"
      local name="$3"
      local common_name="$4"
      local out_dir="$5"
      local extended_key_usage
      local tmp_dir
      local req_config
      local ext_config

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

      mkdir -p "$out_dir"

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
        -CAcreateserial \
        -out "$out_dir/$name.crt" \
        -extfile "$ext_config" \
        >/dev/null 2>&1

      rm -rf "$tmp_dir"
      rm -f "$out_dir/$name.csr"
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
