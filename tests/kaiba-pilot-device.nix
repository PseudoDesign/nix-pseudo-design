{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "kaiba-pilot-device-persistence";
  nodes.machine = {
    imports = [ ../modules/services/kaiba-pilot-device.nix ];
    services.kaibaPilotDevice = {
      enable = true;
      uid = 994;
      gid = 988;
    };
    # Synthetic fixture only. The deployed module never initializes state.
    system.activationScripts.pilotFixture = {
      deps = [ "users" ];
      text = ''
        if ! test -e /var/lib/kaiba-pilot-device; then
          install -d -m 0700 -o 994 -g 988 /var/lib/kaiba-pilot-device
          printf '%s\n' 'synthetic fixture, not a private key' > /var/lib/kaiba-pilot-device/state.json
          chown 994:988 /var/lib/kaiba-pilot-device/state.json
          chmod 0600 /var/lib/kaiba-pilot-device/state.json
        fi
      '';
    };
  };
  testScript = ''
    import shlex

    machine.start(allow_reboot=True)
    machine.wait_for_unit("multi-user.target")
    path = "/var/lib/kaiba-pilot-device"
    unit = machine.succeed("systemd-escape --path --suffix=mount " + path).strip()
    machine.wait_for_unit(unit)

    def protected():
        options = machine.succeed("findmnt -n --mountpoint " + path + " -o OPTIONS").strip().split(",")
        assert {"rw", "nosuid", "nodev", "noexec"} <= set(options), options
        assert machine.succeed("id -u kaiba-pilot-device").strip() == "994"
        assert machine.succeed("id -g kaiba-pilot-device").strip() == "988"
        assert machine.succeed("stat -c '%u:%g:%a' " + path).strip() == "994:988:700"

    protected()
    machine.succeed("runuser -u kaiba-pilot-device -- sh -c 'printf changed-fixture > " + path + "/state.json'")
    before = machine.succeed("sha256sum " + path + "/state.json").split()[0]
    machine.reboot()
    machine.wait_for_unit(unit)
    protected()
    assert machine.succeed("sha256sum " + path + "/state.json").split()[0] == before

    machine.succeed("systemctl stop " + shlex.quote(unit))
    machine.succeed("chmod 0644 " + path + "/state.json")
    machine.fail("systemctl start " + shlex.quote(unit))
    machine.fail("mountpoint -q " + path)
    assert machine.succeed("stat -c %a " + path + "/state.json").strip() == "644"
    assert machine.succeed("sha256sum " + path + "/state.json").split()[0] == before

    machine.succeed("chmod 0600 " + path + "/state.json")
    machine.succeed("mv " + path + "/state.json " + path + "/saved")
    machine.succeed("systemctl reset-failed")
    machine.fail("systemctl start " + shlex.quote(unit))
    machine.fail("test -e " + path + "/state.json")
    machine.succeed("mv " + path + "/saved " + path + "/state.json")
    machine.succeed("systemctl reset-failed")
    machine.succeed("systemctl start " + shlex.quote(unit))
    protected()
  '';
}
