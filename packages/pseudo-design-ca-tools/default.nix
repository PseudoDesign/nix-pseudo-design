{
  coreutils,
  lib,
  makeWrapper,
  openssl,
  stdenvNoCC,
  step-cli,
}:

stdenvNoCC.mkDerivation {
  pname = "pseudo-design-ca-tools";
  version = "0-unstable";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    install -d -m 0755 "$out/bin" "$out/libexec/pseudo-design-ca"
    install -m 0644 config.sh "$out/libexec/pseudo-design-ca/config.sh"
    install -m 0755 bootstrap-offline-ca.sh "$out/libexec/pseudo-design-ca/bootstrap-offline-ca.sh"
    install -m 0755 export-artifacts.sh "$out/libexec/pseudo-design-ca/export-artifacts.sh"
    install -m 0755 install-public-artifacts.sh "$out/libexec/pseudo-design-ca/install-public-artifacts.sh"
    install -m 0755 mint-device-token.sh "$out/libexec/pseudo-design-ca/mint-device-token.sh"
    patchShebangs "$out/libexec/pseudo-design-ca"

    makeWrapper "$out/libexec/pseudo-design-ca/bootstrap-offline-ca.sh" \
      "$out/bin/pseudo-design-ca-bootstrap" \
      --prefix PATH : "${lib.makeBinPath [ coreutils openssl step-cli ]}"
    makeWrapper "$out/libexec/pseudo-design-ca/export-artifacts.sh" \
      "$out/bin/pseudo-design-ca-export" \
      --prefix PATH : "${lib.makeBinPath [ coreutils ]}"
    makeWrapper "$out/libexec/pseudo-design-ca/install-public-artifacts.sh" \
      "$out/bin/pseudo-design-ca-install-public-artifacts" \
      --prefix PATH : "${lib.makeBinPath [ coreutils ]}"
    makeWrapper "$out/libexec/pseudo-design-ca/mint-device-token.sh" \
      "$out/bin/pseudo-design-ca-mint-token" \
      --prefix PATH : "${lib.makeBinPath [ coreutils step-cli ]}"

    runHook postInstall
  '';

  meta = {
    description = "pseudo.design offline CA operation tools";
    mainProgram = "pseudo-design-ca-bootstrap";
    platforms = lib.platforms.linux;
  };
}
