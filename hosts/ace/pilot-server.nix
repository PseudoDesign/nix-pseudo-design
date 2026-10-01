{
  config,
  kaiba-dns,
  kaiba-fleet,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.kaiba.pilotServer;
  runtime = import kaiba-fleet.inputs.nixpkgs { system = "aarch64-linux"; };
  fleet = kaiba-fleet.packages.aarch64-linux.default;
  domain = "pilot.kaiba.pseudo.design";
  socket = "unix:///run/kaiba/identity/local/public/api.sock";
  unpreparedGuard = pkgs.writeShellScript "kaiba-pilot-cutover-unprepared" ''
    echo 'Pilot authority cutover has not been prepared.' >&2
    exit 1
  '';
  operator = pkgs.writeText "kaiba-pilot-operator.json" (
    builtins.toJSON {
      binary = "${fleet}/bin/kaiba-workload-operator";
      inherit socket;
      url = "https://127.0.0.1:18446";
      server_id = "spiffe://${domain}/service/workload-registry";
      dns_zone = domain;
      instance = cfg.dnsEnrollmentInstanceID;
    }
  );
in
{
  imports = [
    kaiba-fleet.nixosModules.pilot-control-plane
    kaiba-fleet.nixosModules.workload-registry
    kaiba-dns.nixosModules.lan-primary
  ];

  options.kaiba.pilotServer = {
    enable = lib.mkEnableOption "Ace's imported pilot control plane and two-host LAN DNS";
    activate = lib.mkEnableOption "starting the reviewed imported authority and promoting Ace to server";
    dnsEnrollmentInstanceID = lib.mkOption {
      type = lib.types.strMatching "[a-z0-9][a-z0-9_-]{0,63}";
      default = "857bfe871759fd73c32f565ab5db97412fd049af9941eab4";
      description = "Existing admitted Ace instance, checked against the import before any workload grant.";
    };
    policyGuard = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Immutable target policy verifier selected by the reviewed migration; no permissive default.";
    };
  };

  config = lib.mkIf cfg.enable {
    # NixOS includes timesyncd but not its optional clock waiter by default.
    # The storage guard already orders after this unit; include the upstream
    # implementation so a fresh boot waits for synchronization before checking
    # the imported policy. PostgreSQL, import validation and APIs follow it.
    systemd.additionalUpstreamSystemUnits = lib.optional cfg.activate "systemd-time-wait-sync.service";
    assertions = [
      {
        assertion = !config.kaiba.lanQualification.enable;
        message = "Ace's migrated server and the expired station qualification profile are mutually exclusive.";
      }
      {
        assertion =
          !cfg.activate || (cfg.policyGuard != null && lib.hasPrefix "/nix/store/" cfg.policyGuard);
        message = "Ace's imported control plane requires its reviewed immutable target policy guard.";
      }
      {
        assertion = config.networking.firewall.enable && !config.networking.nftables.enable;
        message = "Ace's pilot host composition requires its reviewed iptables firewall profile.";
      }
    ];
    systemd.services.kaiba-pilot-import-present = {
      description = "Require the explicitly imported authority directory before mounting it";
      # This check precedes a local filesystem mount. A normal service's
      # implicit After=basic.target/sysinit.target creates a cycle through
      # local-fs.target and can cause PID1 to discard tmpfiles/startup jobs.
      unitConfig.DefaultDependencies = false;
      after = [ "systemd-remount-fs.service" ];
      conflicts = [ "shutdown.target" ];
      before = [
        "srv-kaiba\\x2dpilot.mount"
        "shutdown.target"
      ];
      unitConfig.RequiresMountsFor = [ "/srv" ];
      serviceConfig = {
        Type = "oneshot";
        UMask = "0077";
      };
      script = ''
        set -eu
        test ! -L /srv/kaiba-pilot
        test -d /srv/kaiba-pilot
        # Traverse to exact role-owned 0700 directories without listing the
        # authority root; 0700 here would prevent every service user starting.
        test "$(${pkgs.coreutils}/bin/stat -c '%u:%g:%a' /srv/kaiba-pilot)" = '0:0:711'
        test ! -L /srv/kaiba-pilot/import-manifest.json
        test -f /srv/kaiba-pilot/import-manifest.json
        test "$(${pkgs.coreutils}/bin/stat -c '%u:%g:%a:%h' /srv/kaiba-pilot/import-manifest.json)" = '0:0:600:1'
      '';
    };
    systemd.mounts = [
      {
        description = "Protected imported Kaiba authority state on Ace's existing encrypted root";
        what = "/srv/kaiba-pilot";
        where = "/srv/kaiba-pilot";
        type = "none";
        options = "bind,rw,nosuid,nodev,noexec";
        requires = [ "kaiba-pilot-import-present.service" ];
        after = [ "kaiba-pilot-import-present.service" ];
        bindsTo = [ "dev-mapper-crypted.device" ];
        unitConfig.RequiresMountsFor = [ "/srv" ];
      }
    ];
    # Keep the lifecycle endpoint private to the actual member and operator.
    networking.firewall.extraCommands = ''
      iptables -w -I nixos-fw 1 -d 192.168.8.214/32 -p tcp --dport 18444 -j DROP
      iptables -w -I nixos-fw 1 -d 192.168.8.214/32 -p tcp --dport 18444 -s 192.168.8.247/32 -j nixos-fw-accept
      iptables -w -I nixos-fw 1 -d 192.168.8.214/32 -p tcp --dport 18444 -s 192.168.8.249/32 -j nixos-fw-accept
      iptables -w -I nixos-fw 1 -d 192.168.8.214/32 -p tcp --dport 18444 -i lo -j nixos-fw-accept
    '';
    systemd.services.kaiba-pilot-fleet = {
      bindsTo = [ "firewall.service" ];
      after = [ "firewall.service" ];
    };
    services.kaiba.identity = lib.mkIf cfg.activate {
      role = "server";
      serverListenAddress = "192.168.8.214";
      openFirewall = false;
      pilot.agentAddresses = [ "192.168.8.247" ];
    };
    services.kaiba.pilotControlPlane = {
      enable = true;
      fleetPackage = fleet;
      observationPackage = kaiba-fleet.packages.aarch64-linux.authorities-lan;
      postgresPackage = runtime.postgresql_18;
      stateDirectory = "/srv/kaiba-pilot";
      storageMount = "/srv/kaiba-pilot";
      encryptedDevice = "/dev/mapper/crypted";
      storageDeviceUnit = "dev-mapper-crypted.device";
      importManifestFile = "/srv/kaiba-pilot/import-manifest.json";
      policyGuard = if cfg.activate then cfg.policyGuard else toString unpreparedGuard;
      autoStart = cfg.activate;
      fleetListenAddress = "192.168.8.214:18444";
      databaseClients = [
        {
          user = "kaiba-workload-registry";
          database = "kaiba_pilot_fleet";
        }
      ];
    };
    services.kaiba.workloadRegistry = {
      enable = true;
      package = fleet;
      configFile = "/srv/kaiba-pilot/workload/config.json";
      environmentFile = "/srv/kaiba-pilot/workload/registry.env";
      workloadAPISocket = socket;
      listen = "127.0.0.1:18446";
    };
    systemd.services.kaiba-workload-registry = {
      requires = [
        "kaiba-pilot-fleet.service"
        "kaiba-pilot-observation.service"
        "kaiba-pilot-admission.service"
        "spire-agent.service"
      ];
      after = [
        "kaiba-pilot-fleet.service"
        "kaiba-pilot-observation.service"
        "kaiba-pilot-admission.service"
      ];
      bindsTo = [ "kaiba-pilot-import-guard.service" ];
      serviceConfig.LoadCredential = [
        "reader-cert:/srv/kaiba-pilot/fleet/reader.crt"
        "reader-key:/srv/kaiba-pilot/fleet/reader.key"
        "issuer-cert:/srv/kaiba-pilot/fleet/issuer-ca.crt"
        "observation-ca:/srv/kaiba-pilot/fleet/transport-ca.crt"
        "admission-ca:/srv/kaiba-pilot/fleet/transport-ca.crt"
      ];
    };
    users.groups.kaiba-pilot-operator = { };
    users.users.kaiba-pilot-operator = {
      isSystemUser = true;
      group = "kaiba-pilot-operator";
    };
    systemd.services.kaiba-pilot-operator = {
      description = "One explicit pilot workload grant or reconciliation request";
      requires = [ "kaiba-workload-registry.service" ];
      after = [ "kaiba-workload-registry.service" ];
      bindsTo = [ "kaiba-pilot-import-guard.service" ];
      # Explicit operator invocation only; never a boot-time grant or retry.
      serviceConfig = {
        Type = "oneshot";
        User = "kaiba-pilot-operator";
        Group = "kaiba-pilot-operator";
        ExecStart = "${runtime.python3}/bin/python3 ${kaiba-fleet}/deploy/pilot-lan/operator.py ${operator}";
        LoadCredential = [ "operator-request:/run/kaiba-pilot-operator/request.json" ];
        TimeoutStartSec = "60s";
        Restart = "no";
        UMask = "0077";
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        CapabilityBoundingSet = "";
      };
    };
    kaiba.lanPrimary = {
      enable = true;
      zone = domain;
      listenAddress = "192.168.8.214";
      secondary.address = "192.168.8.247";
      queryAllowedPeers = [ "192.168.8.249" ];
      knotPackage = runtime.knot-dns;
    };
    kaiba.deviceAgent = {
      package = kaiba-dns.packages.aarch64-linux.dns-suite;
      identity = {
        workloadAPISocket = socket;
        controllerSPIFFEID = "spiffe://${domain}/service/dns-controller";
      };
    };
    kaiba.updateController = {
      controller.package = kaiba-dns.packages.aarch64-linux.dns-suite;
      # The imported operational issuer retains loopback port 18443.
      controller.port = 18447;
      publisher.package = kaiba-dns.packages.aarch64-linux.dns-suite;
      identity = {
        workloadAPISocket = socket;
        trustDomain = domain;
        fleetAuthorizationURL = "https://127.0.0.1:18446";
        fleetServerSPIFFEID = "spiffe://${domain}/service/workload-registry";
      };
    };
    systemd.services.kaiba-agent = {
      requires = [
        "spire-agent.service"
        "kaiba-workload-registry.service"
      ];
      after = [
        "spire-agent.service"
        "kaiba-workload-registry.service"
      ];
      bindsTo = [ "kaiba-pilot-import-guard.service" ];
    };
    systemd.services.kaiba-controller = {
      requires = [
        "spire-agent.service"
        "kaiba-workload-registry.service"
      ];
      after = [
        "spire-agent.service"
        "kaiba-workload-registry.service"
      ];
      bindsTo = [ "kaiba-pilot-import-guard.service" ];
    };
    systemd.services.kaiba-publisher.bindsTo = [ "kaiba-pilot-import-guard.service" ];
    systemd.services.kaiba-lan-primary = {
      requires = [ "kaiba-pilot-import-guard.service" ];
      after = [ "kaiba-pilot-import-guard.service" ];
      bindsTo = [ "kaiba-pilot-import-guard.service" ];
    };
    systemd.services.kaiba-lan-primary-credentials = {
      requires = [ "kaiba-pilot-import-guard.service" ];
      after = [ "kaiba-pilot-import-guard.service" ];
      bindsTo = [ "kaiba-pilot-import-guard.service" ];
    };
    # Installation stages the accounts and units. Starting them and exposing
    # the SPIRE authority requires a separate reviewed activation configuration.
    systemd.services.kaiba-workload-registry.wantedBy = lib.mkIf (!cfg.activate) (lib.mkForce [ ]);
    systemd.services.kaiba-agent.wantedBy = lib.mkIf (!cfg.activate) (lib.mkForce [ ]);
    systemd.services.kaiba-controller.wantedBy = lib.mkIf (!cfg.activate) (lib.mkForce [ ]);
    systemd.services.kaiba-publisher.wantedBy = lib.mkIf (!cfg.activate) (lib.mkForce [ ]);
    systemd.services.kaiba-lan-primary.wantedBy = lib.mkIf (!cfg.activate) (lib.mkForce [ ]);
  };
}
