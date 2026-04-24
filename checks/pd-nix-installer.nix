{ lib, nixos-raspberrypi, pkgs, testers }:
let
  mockPrivateKeyPackage = pkgs.writeShellApplication {
    name = "rpi-otp-private-key";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      readonly secretFile=/run/mock/otp.secret

      case "''${1-}" in
        -c)
          [ -s "$secretFile" ]
          ;;
        -w)
          shift
          if [ -z "''${1-}" ]; then
            echo "Missing OTP private key value." >&2
            exit 64
          fi

          install -d -m 0700 /run/mock
          if [ -e "$secretFile" ]; then
            echo "OTP private key already provisioned." >&2
            exit 1
          fi

          printf '%s' "$1" > "$secretFile"
          ;;
        "")
          cat "$secretFile"
          ;;
        *)
          echo "Unexpected arguments: $*" >&2
          exit 64
          ;;
      esac
    '';
  };

  privateKeyExe = lib.getExe mockPrivateKeyPackage;

  mockProvisionPackage = pkgs.writeShellApplication {
    name = "rpi-otp-provision-private-key";
    text = ''
      ${privateKeyExe} -w mock-secret
    '';
  };

  mockDerivedKeyPackage = pkgs.writeShellApplication {
    name = "rpi-otp-derived-key";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      format=""
      saltFile=""
      secretFile=/run/mock/otp.secret

      while [ "$#" -gt 0 ]; do
        case "$1" in
          --format)
            format="$2"
            shift 2
            ;;
          --salt-file)
            saltFile="$2"
            shift 2
            ;;
          *)
            echo "Unexpected arguments: $*" >&2
            exit 64
            ;;
        esac
      done

      [ "$format" = "hex" ] || {
        echo "Unexpected format: $format" >&2
        exit 64
      }

      [ -r "$saltFile" ] || {
        echo "Missing salt file: $saltFile" >&2
        exit 1
      }

      if [ ! -s "$secretFile" ]; then
        echo "OTP private key is missing." >&2
        exit 1
      fi

      printf '%s\n' "derived:$format:$(cat "$saltFile"):$(cat "$secretFile")"
    '';
  };

  mockDiskoInstallPackage = pkgs.writeShellApplication {
    name = "disko-install";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      install -d -m 0700 /run/mock
      printf '%s\n' "$*" > /run/mock/disko-install.args
      touch /run/mock/disko-install.ran
    '';
  };

  mockFlake = pkgs.writeTextDir "flake.nix" ''
    {
      description = "mock installer flake";
      outputs = _: {
        nixosConfigurations.ace = {};
      };
    }
  '';

  mockPkgs = import pkgs.path {
    system = pkgs.stdenv.hostPlatform.system;
    overlays = [
      (final: prev: {
        rpi-otp-private-key = mockPrivateKeyPackage;
      })
    ];
  };
  testSaltFile = pkgs.writeText "rpi-otp-derived-key-test-salt" "test-salt";
in
testers.runNixOSTest {
  name = "pd-nix-installer worflow";

  nodes.installer =
    { lib, ... }:
    {
      _module.args.disko = {
        packages = {
          "${mockPkgs.stdenv.hostPlatform.system}" = {
            "disko-install" = mockDiskoInstallPackage;
          };
        };
      };

      imports = [
        nixos-raspberrypi.nixosModules.rpi-otp-derived-key
        ../modules/pd-installer.nix
      ];

      nixpkgs.pkgs = lib.mkForce mockPkgs;

      services.rpiOtpDerivedKey = {
        package = mockDerivedKeyPackage;
        generateSalt = false;
        saltFile = "/run/secrets/rpi-otp-derived-key-luks.salt";
        initrdSaltSource = testSaltFile;
        secrets.luks = {
          format = "hex";
          path = "/run/secrets/luks.key";
        };
      };

      services.pdInstaller = {
        enable = true;
        flake = mockFlake;
        disk = "/tmp/mockdisk";
        provisionPackage = mockProvisionPackage;
      };

      boot.initrd.systemd.enable = true;
      environment.systemPackages = [ mockPkgs.util-linux ];
      system.stateVersion = "25.11";
    };

  testScript = ''
    start_all()
    installer.wait_for_unit("multi-user.target")

    installer.fail("pd-luks-key-setup")
    installer.fail("test -e /run/mock/otp.secret")
    installer.fail("test -e /run/secrets/luks.key")

    installer.succeed("touch /tmp/mockdisk")
    installer.succeed("printf 'YES\\n' | script -qefc 'pd-nix-install ace' /dev/null")

    installer.succeed("[ \"$(cat /run/mock/otp.secret)\" = \"mock-secret\" ]")
    installer.succeed("[ \"$(cat /run/secrets/luks.key)\" = \"derived:hex:test-salt:mock-secret\" ]")
    installer.succeed("test -f /run/mock/disko-install.ran")
    installer.succeed("grep -F -- '--mode format --disk main /tmp/mockdisk' /run/mock/disko-install.args")
    installer.succeed("grep -F -- '#ace' /run/mock/disko-install.args")

    installer.succeed("rm /run/secrets/luks.key")
    installer.succeed("pd-luks-key-setup")
    installer.succeed("[ \"$(cat /run/secrets/luks.key)\" = \"derived:hex:test-salt:mock-secret\" ]")
  '';
}
