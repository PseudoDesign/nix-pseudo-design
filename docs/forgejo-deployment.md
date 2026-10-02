# Forgejo deployment preparation

The `codex/forgejo-migration` branch prepares Forgejo on Mako and an encrypted
backup receiver on Ace. The host flake pins infrastructure commit
`47347c03e7738051e221a2c60ec828131fa1c1fb`; unrelated input pins remain unchanged.
The [migration runbook](https://github.com/PseudoDesign/kaiba-infra/blob/47347c03e7738051e221a2c60ec828131fa1c1fb/docs/forgejo-migration.md)
records the service configuration, completed checks, unfinished implementation,
cutover gates and rollback sequence.

Both host configurations evaluate successfully. Mako's candidate builds with
resource limits. These are deployment candidates; neither host has been
activated and GitHub remains authoritative. Forgejo Actions stays disabled.

Before temporary activation, provision Mako's runtime backup SSH key and known
hosts file, Ace's dedicated receiver authorized key, and verify off-host encrypted
recovery. Ace currently rejects the workspace SSH key. Malak's sudo and KVM
permissions also prevent builder qualification. Resolve these operator access
paths without changing enrolled pilot credentials or identity policy.

Retain the running generations, compare kernel, initrd, boot arguments, modules,
fstab, unlock and pilot configuration, and use temporary activation with rollback
before persistence. Complete the owner login, recovery, TLS, capacity and CI gates
from the runbook before switching project primacy. No reboot or disk operation is
part of this rollout.
