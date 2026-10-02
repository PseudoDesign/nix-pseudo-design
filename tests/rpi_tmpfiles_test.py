"""Exercise the Pi debugfs rule with no Raspberry Pi OS sudo group present."""
import os
from pathlib import Path
import subprocess
import tempfile

rule = Path(os.environ['DEBUGFS_RULE']).read_text()
assert rule == 'd! /sys/kernel/debug 0700 root root -\n'
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    (root / 'etc/tmpfiles.d').mkdir(parents=True)
    (root / 'etc/group').write_text('root:x:0:\nwheel:x:1:\n')
    (root / 'etc/passwd').write_text('root:x:0:0:root:/root:/bin/sh\n')
    (root / 'sys/kernel/debug').mkdir(parents=True)
    path = root / 'etc/tmpfiles.d/sys-kernel-debug.conf'
    command = [os.environ['SYSTEMD_TMPFILES'], '--root', str(root), '--dry-run',
               '--create', '--boot', '--prefix=/sys/kernel/debug', 'sys-kernel-debug.conf']
    path.write_text('d! /sys/kernel/debug 0750 root sudo -\n')
    old = subprocess.run(command, capture_output=True, text=True)
    assert old.returncode == 65 and "Failed to resolve group 'sudo'" in old.stderr, old
    path.write_text(rule)
    new = subprocess.run(command, capture_output=True, text=True)
    assert new.returncode == 0 and 'Failed to resolve' not in new.stderr, new
print('Missing-group regression reproduced; root-only replacement passes.')
