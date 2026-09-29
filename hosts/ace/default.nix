{ kaiba-infra, ... }:
{
  imports = [
    ../../modules/services/kaiba-pilot-device.nix
    ../../modules/services/kaiba-human-access.nix
    ./identity-pilot.nix
    kaiba-infra.nixosModules.hydra
    kaiba-infra.nixosModules.human-access-backup-receiver
  ];

  services.kaibaHydra = {
    enable = true;
    proxyAddress = "192.168.8.247";
    # Native sandbox smoke test passed on Ace, 2026-09-27 (kernel 6.18.42).
    # Requalify after changing the running kernel or virtualization stack.
    kvm = true;
    backup.enable = true;
    backup.host = "192.168.8.247";
    github.enable = true;
    cachePublish.enable = true;
    ciRuns = {
      enable = true;
      workflowId = 352674431;
      passwordFile = "/var/lib/kaiba-hydra-bootstrap/adam-password";
    };
  };

  # Use the same upstream Hydra package as the qualified infrastructure VMs.
  # Its ARM64 jemalloc supports 16 KiB pages too; the Pi overlay otherwise
  # rebuilds Hydra's Rust/Node toolchains solely to specialize the allocator.
  services.hydra.package = (import kaiba-infra.inputs.nixpkgs { system = "aarch64-linux"; }).hydra;
  services.kaibaHumanAccessBackupReceiver.enable = true;
  services.kaibaHydra.cachePublish.package =
    (import kaiba-infra.inputs.nixpkgs { system = "aarch64-linux"; }).cachix;

  services.kaibaPilotDevice = {
    enable = true;
    # Preserve the IDs that own Ace's existing enrolled key.
    uid = 994;
    gid = 988;
  };

  networking.hostName = "ace";
}
