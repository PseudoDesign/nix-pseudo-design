{
  config,
  disko,
  lib,
  nixos-raspberrypi,
  pkgs,
  ...
}:

let
  otpScheme = config.services.rpiOtpDerivedKey.secrets.luks-key.scheme;
  stagedSaltDir = "/run/rpi-otp-derived-key/disko-install/salt";
  stagedSalt = "${stagedSaltDir}/luks-key";
  stagedKeyDir = "/run/secrets";
  stagedKey = "${stagedKeyDir}/luks.key";
  installedSalt = "${config.disko.rootMountPoint}/var/lib/rpi-otp-derived-key/salt/luks-key";
  rpiOtpProvision =
    pkgs.rpi-otp-derived-key-provision
      or nixos-raspberrypi.packages.${pkgs.stdenv.hostPlatform.system}.rpi-otp-derived-key-provision;
in
{
  imports = with nixos-raspberrypi.nixosModules; [
    raspberry-pi-5.base
    raspberry-pi-5.page-size-16k
    raspberry-pi-5.display-vc4
    rpi-otp-derived-key
    disko.nixosModules.disko
  ];

  boot = {
    initrd.systemd.enable = true;
    loader.raspberry-pi.bootloader = "kernel";
    tmp.useTmpfs = true;
  };

  hardware.raspberry-pi.config.all.base-dt-params = {
    pciex1 = {
      enable = true;
      value = "on";
    };
    pciex1_gen = {
      enable = true;
      value = "3";
    };
  };

  services.rpiOtpDerivedKey = {
    enable = true;
    secrets.luks-key = {
      scheme = lib.mkDefault "legacy-hkdf-v1";
      format = "hex";
      path = "/run/secrets/luks.key";
      neededForBoot = true;
      before = [ "cryptsetup-pre.target" ];
    };
  };

  disko.devices = {
    disk.nvme0-luks = {
      type = "disk";
      device = lib.mkDefault "/dev/nvme0n1";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            priority = 1;
            size = "1G";
            type = "0700";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot/firmware";
              mountOptions = [
                "noatime"
                "noauto"
                "x-systemd.automount"
                "x-systemd.idle-timeout=1min"
              ];
            };
          };

          luks = {
            size = "100%";
            content = {
              type = "luks";
              name = "crypted";
              settings = {
                keyFile = stagedKey;
                allowDiscards = true;
              };
              preCreateHook = ''
                if ${pkgs.cryptsetup}/bin/cryptsetup isLuks "$device" >/dev/null 2>&1; then
                  echo "Refusing to reuse existing LUKS device $device for OTP-derived install key." >&2
                  exit 1
                fi

                ${lib.getExe rpiOtpProvision} stage \
                  --scheme ${lib.escapeShellArg otpScheme} \
                  --format hex \
                  --salt-file "${stagedSalt}" \
                  --out "${stagedKey}"
              '';
              content = {
                type = "lvm_pv";
                vg = "pool";
              };
            };
          };
        };
      };
    };

    lvm_vg.pool = {
      type = "lvm_vg";
      lvs.rootfs = {
        size = "100%";
        content = {
          type = "filesystem";
          format = "ext4";
          mountpoint = "/";
          postMountHook = ''
            ${lib.getExe rpiOtpProvision} install-salt \
              --salt-file "${stagedSalt}" \
              --target-file "${installedSalt}" \
              --cleanup "${stagedSalt}" \
              --cleanup "${stagedKey}"
          '';
        };
      };
    };
  };
}
