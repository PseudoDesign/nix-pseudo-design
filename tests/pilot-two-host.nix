{ pkgs, hosts }:
let
  lib = pkgs.lib;
  aceBase = hosts.ace.config;
  makoBase = hosts.mako.config;
  # Evaluation only. This intentionally nonexistent guard cannot start an
  # authority and never represents a reviewed source-fencing/import receipt.
  ace =
    (hosts.ace.extendModules {
      modules = [
        {
          kaiba.pilotServer.enable = true;
          kaiba.pilotServer.activate = true;
          kaiba.pilotServer.policyGuard = "/nix/store/00000000000000000000000000000000-evaluation-only-refused-policy";
        }
      ];
    }).config;
  mako =
    (hosts.mako.extendModules {
      modules = [
        {
          kaiba.pilotAgent = {
            enable = true;
            activate = true;
          };
        }
      ];
    }).config;
  stagedAce =
    (hosts.ace.extendModules {
      modules = [
        {
          kaiba.pilotServer = {
            enable = true;
            policyGuard = "/nix/store/00000000000000000000000000000000-evaluation-only-refused-policy";
          };
        }
      ];
    }).config;
  stagedMako =
    (hosts.mako.extendModules { modules = [ { kaiba.pilotAgent.enable = true; } ]; }).config;
  missingPolicy =
    (hosts.ace.extendModules {
      modules = [
        {
          kaiba.pilotServer = {
            enable = true;
            activate = true;
          };
        }
      ];
    }).config;
  valid = c: lib.all (entry: entry.assertion) c.assertions;
  unchangedUnit =
    before: after: name:
    before.systemd.units."${name}.service".text == after.systemd.units."${name}.service".text;
  guarded = name: lib.elem "kaiba-pilot-import-guard.service" ace.systemd.services.${name}.bindsTo;
  conflicts =
    (hosts.ace.extendModules {
      modules = [
        {
          kaiba.pilotServer.enable = true;
          kaiba.lanQualification.enable = true;
          kaiba.pilotServer.policyGuard = "/nix/store/00000000000000000000000000000000-evaluation-only-refused-policy";
        }
      ];
    }).config;
in
assert !aceBase.kaiba.pilotServer.enable && !makoBase.kaiba.pilotAgent.enable;
assert valid ace && valid mako;
assert valid stagedAce && valid stagedMako;
assert stagedAce.services.kaiba.identity.role == "standalone";
assert !stagedAce.services.kaiba.pilotControlPlane.autoStart;
assert
  stagedAce.services.kaiba.pilotControlPlane.policyGuard != stagedAce.kaiba.pilotServer.policyGuard;
assert lib.all (name: stagedAce.systemd.services.${name}.wantedBy == [ ]) [
  "kaiba-workload-registry"
  "kaiba-agent"
  "kaiba-controller"
  "kaiba-publisher"
  "kaiba-lan-primary"
];
assert stagedMako.systemd.services.spire-agent.wantedBy == [ ];
assert stagedMako.systemd.services.kaiba-lan-secondary.wantedBy == [ ];
assert stagedMako.systemd.timers.kaiba-member-identity-probe.wantedBy == [ ];
assert lib.any (
  entry:
  entry.message == "Ace's imported control plane requires its reviewed immutable target policy guard."
  && !entry.assertion
) missingPolicy.assertions;
assert lib.any (
  entry:
  entry.message
  == "Ace's migrated server and the expired station qualification profile are mutually exclusive."
  && !entry.assertion
) conflicts.assertions;
assert !ace.kaiba.lanQualification.enable;
assert ace.services.kaiba.identity.role == "server";
assert ace.services.kaiba.identity.trustDomain == aceBase.services.kaiba.identity.trustDomain;
assert
  ace.services.kaiba.identity.pilot.logicalDeviceID
  == aceBase.services.kaiba.identity.pilot.logicalDeviceID;
assert
  ace.services.kaiba.identity.pilot.instanceID == aceBase.services.kaiba.identity.pilot.instanceID;
assert ace.services.kaiba.identity.pilot.agentAddresses == [ "192.168.8.247" ];
assert mako.services.kaiba.identity.role == "agent" && !mako.services.spire.server.enable;
assert mako.services.kaiba.identity.serverAddress == "192.168.8.214";
assert mako.services.spire.agent.settings.agent.rebootstrap_mode == "never";
assert ace.kaiba.lanPrimary.enable && mako.kaiba.lanSecondary.enable;
assert ace.kaiba.lanPrimary.secondary.address == mako.kaiba.lanSecondary.listenAddress;
assert mako.kaiba.lanSecondary.primary.address == ace.kaiba.lanPrimary.listenAddress;
assert ace.kaiba.updateController.controller.port == 18447;
assert ace.kaiba.deviceAgent.endpoint == "https://127.0.0.1:18447";
assert ace.kaiba.updateController.identity.fleetAuthorizationURL == "https://127.0.0.1:18446";
assert ace.services.kaiba.workloadRegistry.listen == "127.0.0.1:18446";
assert ace.services.kaiba.workloadRegistry.configFile == "/srv/kaiba-pilot/workload/config.json";
assert ace.services.kaiba.workloadRegistry.policy == null;
assert !mako.kaiba.deviceAgent.enable && !mako.kaiba.updateController.enable;
assert ace.systemd.services.kaiba-pilot-operator.wantedBy == [ ];
assert ace.systemd.services.kaiba-pilot-operator.serviceConfig.Restart == "no";
assert lib.all guarded [
  "kaiba-workload-registry"
  "kaiba-pilot-operator"
  "kaiba-agent"
  "kaiba-controller"
  "kaiba-publisher"
  "kaiba-lan-primary"
  "kaiba-lan-primary-credentials"
];
assert lib.elem "kaiba-workload-registry" ace.users.groups.kaiba-pilot-dbclients.members;
assert lib.elem "firewall.service" ace.systemd.services.kaiba-pilot-fleet.bindsTo;
assert ace.networking.firewall.allowedTCPPorts == aceBase.networking.firewall.allowedTCPPorts;
assert mako.networking.firewall.allowedTCPPorts == makoBase.networking.firewall.allowedTCPPorts;
assert lib.hasInfix "--dport 18444 -j DROP" ace.networking.firewall.extraCommands;
assert lib.hasInfix "--dport 18444 -s 192.168.8.247/32" ace.networking.firewall.extraCommands;
assert ace.systemd.units."srv-kaiba\\x2dpilot.mount".enable;
assert lib.all (name: unchangedUnit aceBase ace name) [
  "hydra-server"
  "hydra-evaluator"
  "hydra-queue-runner"
  "postgresql"
  "sshd"
  "kaiba-pilot-existing-state"
];
assert lib.all (name: unchangedUnit makoBase mako name) [
  "postgresql"
  "sshd"
  "nginx"
  "kaiba-ssh-ca"
  "kaiba-pilot-existing-state"
];
assert ace.system.build.initialRamdisk.outPath == aceBase.system.build.initialRamdisk.outPath;
assert mako.system.build.initialRamdisk.outPath == makoBase.system.build.initialRamdisk.outPath;
assert ace.system.build.kernel.outPath == aceBase.system.build.kernel.outPath;
assert mako.system.build.kernel.outPath == makoBase.system.build.kernel.outPath;
assert ace.fileSystems == aceBase.fileSystems && mako.fileSystems == makoBase.fileSystems;
assert mako.systemd.services.spire-agent.serviceConfig.MemoryMax == "256M";
assert mako.systemd.services.kaiba-lan-secondary.serviceConfig.MemoryMax == "256M";
pkgs.runCommand "kaiba-two-host-composition" { } ''
  mkdir -p "$out"
  cat > "$out/report.json" <<'EOF'
  {"schema_version":"kaiba.two-host-composition-check/v1alpha1","passed":true,"evaluation_only":true,"live_cutover":false,"checks":["disabled-defaults","staging-always-denies-authority","staging-does-not-autostart","activation-requires-policy","mutually-exclusive-trial-profile","preserved-owner-identity","no-member-authority","current-admission-dependencies","distinct-issuer-and-dns-ports","real-remote-secondary","private-listeners-and-source-firewall","explicit-operator-grants","existing-applications-and-storage-preserved","member-memory-limits"]}
  EOF
''
