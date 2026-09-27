{ kaiba-infra, ... }:
{
  imports = [
    ../../modules/services/kaiba-pilot-device.nix
    kaiba-infra.nixosModules.hydra
  ];

  services.kaibaHydra = {
    enable = true;
    proxyAddress = "192.168.8.247";
    # Native sandbox smoke test passed on Ace, 2026-09-27 (kernel 6.12.47).
    # Requalify after changing the running kernel or virtualization stack.
    kvm = true;
    backup.enable = true;
    backup.host = "192.168.8.247";
  };

  services.kaibaPilotDevice = {
    enable = true;
    # Preserve the IDs that own Ace's existing enrolled key.
    uid = 994;
    gid = 988;
  };

  networking.hostName = "ace";
}
