{
  writeShellApplication,
  lib,
  rpi-otp-private-key,
  provisionPackage,
  setupPackage,
  diskoInstallPackage,
  flakePath,
  nixosConfiguration,
  disk,
  keyFile,
}:
let
  # Resolve the helper executables once so the generated script can call them directly.
  privateKeyCheckExe = lib.getExe rpi-otp-private-key;
  provisionPrivateKeyExe = lib.getExe provisionPackage;
  setupCommandExe = lib.getExe setupPackage;
  diskoInstallExe = "${diskoInstallPackage}/bin/disko-install";
in
writeShellApplication {
  name = "pd-nix-install";
  text = ''
    readonly EX_USAGE=64
    readonly EX_NOINPUT=66
    readonly EX_SOFTWARE=70
    readonly EX_NOPERM=77
    readonly FLAKE_PATH='${flakePath}'
    readonly DEFAULT_CONFIGURATION='${nixosConfiguration}'

    # Allow the caller to override only the flake output name, keeping the
    # installer source itself pinned by configuration.
    configurationName="$DEFAULT_CONFIGURATION"

    if [ "$#" -gt 1 ]; then
      echo "Usage: pd-nix-install [configuration]" >&2
      exit "$EX_USAGE"
    fi

    if [ "$#" -eq 1 ]; then
      configurationName="$1"
    fi

    flakeRef="$FLAKE_PATH#$configurationName"

    if [ "$EUID" -ne 0 ]; then
      echo "This command must be run as root." >&2
      exit "$EX_NOPERM"
    fi

    if [ ! -e '${disk}' ]; then
      echo "Target disk '${disk}' does not exist." >&2
      exit "$EX_NOINPUT"
    fi

    # The confirmation prompt and disko formatting step both expect a real TTY.
    if [ ! -t 0 ]; then
      echo "This command requires an interactive terminal for confirmation." >&2
      exit "$EX_NOINPUT"
    fi

    # Surface the derived values before we touch OTP state or the target disk.
    echo "About to install NixOS with the following settings:"
    echo "  source flake: $flakeRef"
    echo "  configuration: $configurationName"
    echo "  target disk: ${disk}"
    echo "  derived key file: ${keyFile}"
    echo
    echo "This will:"
    echo "  1. Provision the Raspberry Pi OTP private key if it is unset."
    echo "  2. Derive the LUKS key into ${keyFile}."
    echo "  3. Run disko-install in format mode against ${disk}."
    echo
    echo "WARNING: This may permanently program OTP and will continue into disk formatting."
    echo "Type YES to continue or anything else to cancel."
    read -r confirmation
    if [ "$confirmation" != "YES" ]; then
      echo "Cancelled."
      exit 1
    fi

    # Provisioning remains explicit and guarded by the OTP helper itself.
    if ! ${privateKeyCheckExe} -c >/dev/null 2>&1; then
      echo "Raspberry Pi OTP private key is unset; provisioning it now."
      ${provisionPrivateKeyExe}
    fi

    # Reuse the standalone setup command so installer and manual recovery paths
    # share exactly the same key-derivation behavior.
    echo "Deriving the LUKS key into ${keyFile}."
    ${setupCommandExe}

    if [ ! -s '${keyFile}' ]; then
      echo "Expected derived LUKS key at '${keyFile}'." >&2
      exit "$EX_SOFTWARE"
    fi

    # Leave the final destructive confirmation to disko itself.
    exec ${diskoInstallExe} \
      --flake "$flakeRef" \
      --mode format \
      --disk main '${disk}'
  '';

  meta = {
    description = "Interactive pseudo.design NixOS installer command.";
  };
}
