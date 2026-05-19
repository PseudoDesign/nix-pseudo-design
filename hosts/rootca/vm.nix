{
  lib,
  pkgs,
  ...
}:

let
  pkcs11StateDir = "/var/lib/pseudo-design/rootca-vm-pkcs11";
  pkcs11TokenDir = "${pkcs11StateDir}/tokens";
  pkcs11UserPinFile = "${pkcs11StateDir}/user-pin";
  pkcs11SoPinFile = "${pkcs11StateDir}/so-pin";
  softHsmConfig = "${pkcs11StateDir}/softhsm2.conf";
  softHsmModule = "${pkgs.softhsm}/lib/softhsm/libsofthsm2.so";
  rootTokenLabel = "pseudo-design-root";
  rootKms = "pkcs11:module-path=${softHsmModule};token=${rootTokenLabel}?pin-source=${pkcs11UserPinFile}";
  rootKey = "pkcs11:id=1000;object=root-ca";
in
{
  boot.loader.grub.devices = [ "/dev/vda" ];
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  networking.useDHCP = lib.mkDefault true;

  services.getty.autologinUser = "root";

  environment = {
    sessionVariables = {
      PSEUDO_DESIGN_CA_ROOT_KMS = rootKms;
      PSEUDO_DESIGN_CA_ROOT_KEY = rootKey;
      SOFTHSM2_CONF = softHsmConfig;
    };

    systemPackages = [
      pkgs.softhsm
      pkgs.step-kms-plugin
    ];
  };

  security.sudo.extraConfig = ''
    Defaults env_keep += "PSEUDO_DESIGN_CA_ROOT_KMS PSEUDO_DESIGN_CA_ROOT_KEY SOFTHSM2_CONF"
  '';

  systemd.tmpfiles.rules = [
    "d ${pkcs11StateDir} 0700 root root -"
    "d ${pkcs11TokenDir} 0700 root root -"
  ];

  systemd.services.pseudo-design-rootca-vm-pkcs11 = {
    description = "Initialize VM-local SoftHSM PKCS#11 token for the pseudo.design root CA";
    wantedBy = [ "multi-user.target" ];
    before = [
      "getty.target"
      "sshd.service"
    ];
    path = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.openssl
      pkgs.softhsm
      pkgs.step-cli
      pkgs.step-kms-plugin
    ];
    environment.SOFTHSM2_CONF = softHsmConfig;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      UMask = "0077";
    };
    script = ''
            set -euo pipefail

            install -d -m 0700 ${pkcs11StateDir} ${pkcs11TokenDir}

            create_pin() {
              if [ ! -s "$1" ]; then
                openssl rand -hex 24 | tr -d '\n' > "$1"
              fi
              chmod 0600 "$1"
            }

            create_pin ${pkcs11UserPinFile}
            create_pin ${pkcs11SoPinFile}

            cat > ${softHsmConfig} <<'EOF'
      directories.tokendir = ${pkcs11TokenDir}
      objectstore.backend = file
      EOF
            chmod 0600 ${softHsmConfig}

            if ! softhsm2-util --show-slots | grep -Eq 'Label:[[:space:]]*${rootTokenLabel}$'; then
              softhsm2-util \
                --init-token \
                --free \
                --label ${rootTokenLabel} \
                --pin "$(cat ${pkcs11UserPinFile})" \
                --so-pin "$(cat ${pkcs11SoPinFile})"
            fi

            if ! step kms key --kms ${lib.escapeShellArg rootKms} ${lib.escapeShellArg rootKey} >/dev/null 2>&1; then
              step kms create \
                --kty EC \
                --crv P256 \
                --kms ${lib.escapeShellArg rootKms} \
                ${lib.escapeShellArg rootKey} >/dev/null
            fi
    '';
  };

  virtualisation.vmVariant.virtualisation = {
    diskSize = 8192;
    graphics = false;
    memorySize = 1024;
    forwardPorts = [
      {
        from = "host";
        host.port = 2222;
        guest.port = 22;
      }
    ];
  };
}
