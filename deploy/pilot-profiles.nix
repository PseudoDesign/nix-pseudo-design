# Explicit active profiles for the already imported/admitted two-host pilot.
# The caller must supply the exact reviewed immutable guard with Nix reference
# context; this file neither imports private state nor selects a new policy.
{
  hosts,
  policyGuard,
  guardAdmittedMember,
}:
let
  guard = toString policyGuard;
  ace = hosts.ace.extendModules {
    modules = [
      {
        kaiba.pilotServer = {
          enable = true;
          activate = true;
          policyGuard = guard;
        };
      }
    ];
  };
  mako = hosts.mako.extendModules {
    modules = [
      {
        kaiba.pilotAgent = {
          enable = true;
          activate = true;
          admittedState.enable = guardAdmittedMember;
        };
      }
    ];
  };
  unchanged =
    before: after: units:
    builtins.all (
      name: before.systemd.units."${name}.service".text == after.systemd.units."${name}.service".text
    ) units
    && before.system.build.kernel.outPath == after.system.build.kernel.outPath
    && before.system.build.initialRamdisk.outPath == after.system.build.initialRamdisk.outPath
    && before.fileSystems == after.fileSystems;
in
assert builtins.match "/nix/store/[a-z0-9]{32}-[^/]+" guard != null;
assert builtins.hasContext guard;
assert builtins.isBool guardAdmittedMember;
assert builtins.all (entry: entry.assertion) ace.config.assertions;
assert builtins.all (entry: entry.assertion) mako.config.assertions;
assert unchanged hosts.ace.config ace.config [
  "hydra-server"
  "hydra-evaluator"
  "hydra-queue-runner"
  "postgresql"
  "sshd"
  "kaiba-pilot-existing-state"
];
assert unchanged hosts.mako.config mako.config [
  "nginx"
  "keycloak"
  "postgresql"
  "kaiba-ssh-ca"
  "sshd"
  "kaiba-pilot-existing-state"
];
{
  configurations = { inherit ace mako; };
  systems = {
    ace = ace.config.system.build.toplevel;
    mako = mako.config.system.build.toplevel;
  };
}
