{
  config,
  kaiba-dns,
  kaiba-fleet,
  lib,
  ...
}:
let
  cfg = config.kaiba.pilotAgent;
  runtime = import kaiba-fleet.inputs.nixpkgs { system = "aarch64-linux"; };
in
{
  imports = [
    kaiba-fleet.nixosModules.spiffe
    kaiba-dns.nixosModules.lan-secondary
  ];
  options.kaiba.pilotAgent.enable = lib.mkEnableOption "Mako's explicitly admitted SPIRE Agent and LAN DNS secondary";
  options.kaiba.pilotAgent.activate = lib.mkEnableOption "starting Mako's admitted agent and provisioned DNS replica";

  config = lib.mkIf cfg.enable {
    services.kaiba.identity = {
      enable = true;
      role = "agent";
      trustDomain = "pilot.kaiba.pseudo.design";
      serverAddress = "192.168.8.214";
      agentPackage = runtime.spire.agent;
      trustBundleFile = "/var/lib/kaiba/identity/member-bootstrap/trust-bundle.pem";
      joinTokenFile = "/run/kaiba-member-admission/join-token";
    };
    # These are additional services on an existing 2 GiB application host.
    systemd.services.spire-agent.serviceConfig = {
      MemoryHigh = "128M";
      MemoryMax = "256M";
      TasksMax = 128;
    };
    users.groups.kaiba-member-identity-probe = { };
    users.users.kaiba-member-identity-probe = {
      isSystemUser = true;
      group = "kaiba-member-identity-probe";
    };
    systemd.services.kaiba-member-identity-probe = {
      description = "Verify Mako's explicitly registered local workload identity";
      requires = [ "spire-agent.service" ];
      after = [ "spire-agent.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "kaiba-member-identity-probe";
        Group = "kaiba-member-identity-probe";
        ExecStart = "${kaiba-fleet.packages.aarch64-linux.spiffe-probe}/bin/kaiba-spiffe-probe fetch --socket unix:///run/kaiba/identity/local/public/api.sock --timeout 15s";
        TimeoutStartSec = "20s";
        UMask = "0077";
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        CapabilityBoundingSet = "";
        RestrictAddressFamilies = [ "AF_UNIX" ];
        MemoryMax = "128M";
        TasksMax = 64;
      };
    };
    systemd.timers.kaiba-member-identity-probe = {
      wantedBy = lib.optional cfg.activate "timers.target";
      timerConfig = {
        OnBootSec = "1min";
        OnUnitInactiveSec = "5min";
        Unit = "kaiba-member-identity-probe.service";
      };
    };
    kaiba.lanSecondary = {
      enable = true;
      zone = "pilot.kaiba.pseudo.design";
      listenAddress = "192.168.8.247";
      primary.address = "192.168.8.214";
      queryAllowedPeers = [ "192.168.8.249" ];
      knotPackage = runtime.knot-dns;
      transferSecretFile = "/var/lib/kaiba/identity/member-bootstrap/dns-transfer.secret";
    };
    systemd.services.kaiba-lan-secondary.serviceConfig = {
      MemoryHigh = "128M";
      MemoryMax = "256M";
      TasksMax = 128;
    };
    systemd.services.spire-agent.wantedBy = lib.mkIf (!cfg.activate) (lib.mkForce [ ]);
    systemd.services.kaiba-lan-secondary.wantedBy = lib.mkIf (!cfg.activate) (lib.mkForce [ ]);
  };
}
