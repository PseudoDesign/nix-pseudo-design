"""Exercise PID1's ordering graph using the rendered pilot preflight unit."""
import os
from pathlib import Path
import re
import subprocess
import tempfile


def verify(preflight, mount, legacy):
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        units = root / "etc/systemd/system"
        units.mkdir(parents=True)
        (root / "run/systemd").mkdir(parents=True)
        (root / "srv/kaiba-pilot").mkdir(parents=True)
        (root / "bin").mkdir()
        executable = root / "bin/true"
        executable.write_text("#!/bin/sh\nexit 0\n")
        executable.chmod(0o755)
        # Verification checks executable existence, without executing it. Keep
        # the rendered unit's dependencies and replace only its store command.
        preflight = re.sub(r"(?m)^ExecStart=.*$", "ExecStart=/bin/true", preflight)
        if legacy:
            preflight = preflight.replace("DefaultDependencies=false", "DefaultDependencies=true")
        fixtures = {
            "kaiba-pilot-import-present.service": preflight,
            "srv-kaiba\\x2dpilot.mount": mount,
            "multi-user.target": "[Unit]\nRequires=basic.target avahi-daemon.service\nAfter=basic.target\n",
            "basic.target": "[Unit]\nRequires=sysinit.target\nWants=sockets.target\nAfter=sysinit.target sockets.target\n",
            "sysinit.target": "[Unit]\nDefaultDependencies=no\nWants=local-fs.target systemd-tmpfiles-setup.service\nAfter=local-fs.target systemd-tmpfiles-setup.service\n",
            "local-fs.target": "[Unit]\nDefaultDependencies=no\nRequires=srv-kaiba\\x2dpilot.mount\n",
            "sockets.target": "[Unit]\nDefaultDependencies=no\nWants=avahi-daemon.socket\n",
            "systemd-tmpfiles-setup.service": "[Unit]\nDefaultDependencies=no\nAfter=local-fs.target\nBefore=sysinit.target\n[Service]\nType=oneshot\nExecStart=/bin/true\n",
            "systemd-remount-fs.service": "[Unit]\nDefaultDependencies=no\n[Service]\nType=oneshot\nExecStart=/bin/true\n",
            "avahi-daemon.socket": "[Unit]\nAfter=systemd-tmpfiles-setup.service\n[Socket]\nListenStream=/run/avahi-daemon/socket\n",
            "avahi-daemon.service": "[Unit]\nRequires=avahi-daemon.socket\n[Service]\nExecStart=/bin/true\n",
            "shutdown.target": "[Unit]\nDefaultDependencies=no\n",
            "umount.target": "[Unit]\nDefaultDependencies=no\n",
            "local-fs-pre.target": "[Unit]\nDefaultDependencies=no\n",
        }
        for name, text in fixtures.items():
            (units / name).write_text(text)
        result = subprocess.run(
            [os.environ["SYSTEMD_ANALYZE"], "verify", "--root=" + str(root),
             "--man=no", "multi-user.target"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            timeout=20, env={**os.environ, "SYSTEMD_LOG_LEVEL": "warning"},
        )
        if legacy:
            # PID1 can return success after deleting nonessential jobs to
            # break a cycle. An exit-status-only test misses this boot defect.
            assert "ordering cycle" in result.stdout, result.stdout
            # Which dispensable job is removed varies by systemd version and
            # graph traversal; the regression is deletion of startup work.
            assert re.search(r"Job (?:systemd-tmpfiles-setup.service|local-fs.target|sockets.target)/start deleted", result.stdout), result.stdout
        else:
            assert result.returncode == 0 and "ordering cycle" not in result.stdout and "deleted to break" not in result.stdout, result.stdout


preflight = Path(os.environ["PREFLIGHT_UNIT"]).read_text()
mount = Path(os.environ["PILOT_MOUNT_UNIT"]).read_text()
assert "DefaultDependencies=false" in preflight
verify(preflight, mount, legacy=True)
verify(preflight, mount, legacy=False)
print("Legacy boot ordering cycle reproduced; rendered early preflight passes PID1 graph verification.")
