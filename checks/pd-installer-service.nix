{ lib, pkgs, testers }:
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

  mockLuksKeyPackage = pkgs.writeShellApplication {
    name = "rpi-otp-luks-key";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      salt="$1"
      secretFile=/run/mock/otp.secret

      if [ ! -s "$secretFile" ]; then
        echo "OTP private key is missing." >&2
        exit 1
      fi

      printf '%s\n' "derived:''${salt}:$(cat "$secretFile")"
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
in
testers.runNixOSTest {
  name = "pd-installer-service provisions OTP only from the install command";

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
        ../modules/rpi-otp-luks-key
        ../modules/rpi-installer-service.nix
      ];

      nixpkgs.pkgs = lib.mkForce mockPkgs;

      services.rpiOtpLuksKey = {
        enable = true;
        package = mockLuksKeyPackage;
        salt = "test-salt";
        keyFile = "/run/secrets/luks.key";
      };

      services.pdInstaller = {
        enable = true;
        flake = mockFlake;
        disk = "/tmp/mockdisk";
        provisionPackage = mockProvisionPackage;
      };

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
    installer.succeed("[ \"$(cat /run/secrets/luks.key)\" = \"derived:test-salt:mock-secret\" ]")
    installer.succeed("test -f /run/mock/disko-install.ran")
    installer.succeed("grep -F -- '--mode format --disk main /tmp/mockdisk' /run/mock/disko-install.args")
    installer.succeed("grep -F -- '#ace' /run/mock/disko-install.args")

    installer.succeed("rm /run/secrets/luks.key")
    installer.succeed("pd-luks-key-setup")
    installer.succeed("[ \"$(cat /run/secrets/luks.key)\" = \"derived:test-salt:mock-secret\" ]")
  '';
}
