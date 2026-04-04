{
  stdenvNoCC,
  fetchFromGitHub,
  lib,
  makeWrapper,
  coreutils,
  gnused,
  gawk,
  gnugrep,
  which,
  xxd,
  libraspberrypi,
}:

stdenvNoCC.mkDerivation {
  pname = "rpi-otp-private-key";
  version = "2025.12.08-2712";

  src = fetchFromGitHub {
    owner = "raspberrypi";
    repo = "rpi-eeprom";
    rev = "v2025.12.08-2712";
    hash = "sha256-WByNvK115PbIJFMkZ4TYjU4QdNkyMrswAWcMlPIw2h4=";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 tools/rpi-otp-private-key \
      $out/bin/rpi-otp-private-key

    patchShebangs $out/bin/rpi-otp-private-key

    wrapProgram $out/bin/rpi-otp-private-key \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          gnused
          gawk
          gnugrep
          which
          xxd
          libraspberrypi
        ]
      }

    runHook postInstall
  '';

  meta = with lib; {
    description = "Read or program the Raspberry Pi OTP private key.";
    homepage = "https://github.com/raspberrypi/rpi-eeprom";
    license = licenses.bsd3;
    mainProgram = "rpi-otp-private-key";
    platforms = platforms.linux;
  };
}
