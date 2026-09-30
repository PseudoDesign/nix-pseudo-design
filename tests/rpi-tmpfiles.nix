{ pkgs, hosts }:
let
  path = "tmpfiles.d/sys-kernel-debug.conf";
  rule = hosts.ace.config.environment.etc.${path}.text;
in
assert rule == hosts.mako.config.environment.etc.${path}.text;
assert !(builtins.hasAttr "sudo" hosts.ace.config.users.groups);
pkgs.runCommand "rpi-debugfs-tmpfiles-check"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    DEBUGFS_RULE = pkgs.writeText "sys-kernel-debug.conf" rule;
    SYSTEMD_TMPFILES = "${pkgs.systemd}/bin/systemd-tmpfiles";
  }
  ''
    python3 ${./rpi_tmpfiles_test.py}
    touch "$out"
  ''
