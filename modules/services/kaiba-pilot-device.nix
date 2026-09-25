{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  cfg = config.services.kaibaPilotDevice;
  account = "kaiba-pilot-device";
  state = "/var/lib/kaiba-pilot-device";
  mountUnit = "${utils.escapeSystemdPath state}.mount";
  check = pkgs.writeShellScript "kaiba-pilot-existing-state-check" ''
    set -eu
    export LC_ALL=C
    # Only metadata is inspected. Do not create, read, replace or chown key state.
    test ! -L ${state}
    test -d ${state}
    test "$(${pkgs.coreutils}/bin/stat -c '%u:%g:%a' ${state})" = '${toString cfg.uid}:${toString cfg.gid}:700'
    test ! -L ${state}/state.json
    test -f ${state}/state.json
    test "$(${pkgs.coreutils}/bin/stat -c '%u:%g:%a:%h' ${state}/state.json)" = '${toString cfg.uid}:${toString cfg.gid}:600:1'
  '';
in
{
  options.services.kaibaPilotDevice = {
    enable = lib.mkEnableOption "persistence for an already-enrolled Kaiba pilot device";
    uid = lib.mkOption {
      type = lib.types.ints.positive;
      description = "Existing pilot account UID; must match ownership of enrolled state.";
    };
    gid = lib.mkOption {
      type = lib.types.ints.positive;
      description = "Existing pilot group GID; must match ownership of enrolled state.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.${account}.gid = cfg.gid;
    users.users.${account} = {
      inherit (cfg) uid;
      group = account;
      isSystemUser = true;
      home = "/var/empty";
      createHome = false;
      shell = "${pkgs.shadow}/bin/nologin";
    };

    systemd.services.kaiba-pilot-existing-state = {
      description = "Check existing Kaiba pilot credential ownership without reading keys";
      before = [ mountUnit ];
      after = [ "local-fs-pre.target" ];
      unitConfig = {
        DefaultDependencies = false;
        RequiresMountsFor = [
          "/var/lib"
          "/nix/store"
        ];
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = check;
        UMask = "0077";
      };
    };

    systemd.mounts = [
      {
        description = "Protected mount for existing Kaiba pilot credentials";
        what = state;
        where = state;
        type = "none";
        options = "bind,rw,nosuid,nodev,noexec";
        wantedBy = [ "multi-user.target" ];
        requires = [ "kaiba-pilot-existing-state.service" ];
        after = [ "kaiba-pilot-existing-state.service" ];
        unitConfig.RequiresMountsFor = [ "/var/lib" ];
      }
    ];
  };
}
