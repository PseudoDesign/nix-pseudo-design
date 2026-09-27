{ pkgs }:
let
  otpHelper = pkgs.writeShellScriptBin "rpi-otp-private-key" ''
    if [ "''${1-}" = -c ]; then
      test "''${KAIBA_TEST_BAD_OTP-0}" = 0
    else
      printf '0123456789abcdef\nFEDCBA9876543210\n'
    fi
  '';
  legacyKey = import ../hosts/ace/legacy-luks-key.nix { inherit pkgs otpHelper; };
in
pkgs.runCommand "ace-legacy-luks-key-compatibility"
  {
    nativeBuildInputs = [ pkgs.python3 ];
  }
  ''
    python3 - <<'PY'
    import hashlib, os, subprocess
    command = ["${legacyKey}/bin/ace-legacy-luks-key"]
    # The running generation strips the OTP helper's trailing newline, then
    # hashes the literal salt plus the remaining bytes and one final newline.
    expected = hashlib.sha256(b"default-salt0123456789abcdef\nFEDCBA9876543210\n").hexdigest().encode() + b"\n"
    assert subprocess.check_output(command) == expected
    failed = subprocess.run(command, env=dict(os.environ, KAIBA_TEST_BAD_OTP="1"), capture_output=True)
    assert failed.returncode != 0 and failed.stdout == b""
    PY
    touch "$out"
  ''
