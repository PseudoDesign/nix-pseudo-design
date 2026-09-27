# Hydra CI integration qualification — 2026-09-27 UTC

Ace test-activated the GitHub status and Cachix publication integrations, then
made that same configuration persistent at 18:48:46 UTC after owner approval.
The service update preserves the existing kernel and has not rebooted either
host.

| Item | Revision or closure |
| --- | --- |
| Merged infrastructure integration | `0a64f953151cf4c1ee01c0605aa690e341ee5497` |
| Host configuration tested | `f46fc8fa678e36456e81cacd5cef8bfa3c4db4d4` |
| Ace current and persistent generation | `/nix/store/7jncgkzy00g2p3qqwqa1vwwdw835117g-nixos-system-ace-26.05.20260807.ee48b14` |
| Previous retained generation | `/nix/store/6rq3psyd25v34jlj402agjs6vafdy5dg-nixos-system-ace-26.05.20260807.ee48b14` |

The original infrastructure revision was
`596271d006408de1d9ba33888d5b4eb33b83dfdc`. Its merged revision has the same
source hash and produces exactly the same Ace system closure. The host input
now pins the merged revision. The merged infrastructure main commit also
completed [Hydra build 12](https://hydra.pseudo.design/build/12), reporting both
pending and successful GitHub statuses automatically.

## Host acceptance

The candidate's kernel, initrd, filesystem table, pilot metadata-check unit and
protected mount unit match the running baseline. Kernel 6.18.42, pilot UID
994/GID 988, directory mode 0700, state-file mode 0600 with one link, and disabled
swap are preserved. The complete public pilot status was identical before and
after activation. No credential, enrollment or unlock state was replaced.

Activation used the boot-automount procedure in `hydra-live-rollout.md`, keeping
the shell in the real `/boot/firmware` filesystem throughout. The test switch
completed at 16:56 UTC, all Hydra services returned, and verified HTTPS through
Mako continued serving the API. Neither a kernel change nor a reboot is needed
for this update. The permanent switch used the same mount procedure and again
verified identical public pilot status and no failed services. The previous
generation is additionally rooted at
`/nix/var/nix/gcroots/kaiba-hydra-ci-before-persist-20260927`; use the same
boot-mount preparation when activating it for rollback.

Cachix uses the ordinary upstream ARM64 package, as Hydra already does. The
publisher uses the host's configured Nix package. Using the Pi overlay's default
packages had attempted unrelated Rust/Haskell toolchain builds; that build was
stopped. The accepted runtime closure adds about 40 MiB. Free NVMe space was
22 GiB after qualification, above the 20 GiB queue guard. Downloaded toolchain
paths remain subject to the host's normal Nix retention policy.

## Fresh ARM64 execution

The ten jobs from provisioning main revision
`9da2b998c021651321b6f25f3c38c68edf079aa8` were forcibly rebuilt serially on Ace,
with one build and two cores. Hydra's queue runner was paused during execution
and automatically resumed afterwards. A disk guard enforced the 20 GiB reserve.

| Job | Fresh execution (seconds) | Result |
| --- | ---: | --- |
| copied-storage-vm | 126.57 | Passed and reproduced |
| device-secret-execution-vm | 37.63 | Passed and reproduced |
| device-secret-offline-storage-vm | 76.76 | Passed and reproduced |
| device-secret-storage-development-vm | 68.20 | Passed and reproduced |
| device-secret-target-artifacts | 54.12 | Passed and reproduced |
| device-secret-target-luks-vm | 71.15 | Passed and reproduced |
| enrollment-storage-vm | 69.15 | Assertions passed; report needed the correction below |
| stable-campaign-provisioner-unsigned-artifacts | 51.07 | Passed and reproduced |
| stable-handoff-aarch64-kexec-file-vm | 67.96 | Passed and reproduced |
| stable-verifier-aarch64-kexec-vm | 62.80 | Passed and reproduced |

The enrollment report exported random boot UUIDs, so Nix correctly rejected its
reproducibility comparison. Provisioning PR #92 preserves the real boot-ID
assertions and replaces only the exported UUIDs with stable boot sequence
numbers. Its new derivation
`/nix/store/6rn7m42v3j8fc4mhnhfb5gxgd55inc5n-vm-test-run-kaiba-enrollment-storage.drv`
passed a fresh build and a forced rebuild in about 56 seconds each. The complete
two-pass run completed at 16:47 UTC with byte-identical output. That derivation
is unchanged in the committed provisioning branch.

The VM evidence shows real KVM use: open `/dev/kvm` and KVM VM/vCPU descriptors
were recorded for seven original VM checks; the handoff guests explicitly
reported KVM hypervisor services. The corrected enrollment guests reported KVM
on both boots and both executions. The two artifact checks do not boot guests.

Root-only execution records remain at `/var/tmp/kaiba-hydra-fresh-20260927` and
`/var/tmp/kaiba-hydra-enrollment-fixed`. These contain synthetic test evidence,
not enrolled host state. The separately stamped provisioner artifact changes
derivation with the source revision; the corresponding PR check also passed.

## GitHub and Cachix

The operator installed separate root-owned 0600 token files beneath
`/var/lib/kaiba-hydra-secrets` (0700). Systemd loads them as credentials. The
notifier's private configuration is under `/run/kaiba-hydra-notify` with directory
mode 0700 and file mode 0600; neither token enters the Nix store or Hydra backups.

The first GitHub token was denied with `statuses=write` required. The notifier
persisted all eleven failed deliveries. After the operator replaced the token,
replaying the verified successful builds produced all eleven expected GitHub
statuses: one on infrastructure `567d552e0cc65cf8a2473b7b922b287769f94307`, and
ten on provisioning `9da2b998c021651321b6f25f3c38c68edf079aa8`. Each is successful
and links to its corresponding Hydra build (1 through 11). The earlier retry
records subsequently retried successfully and the retry queue is empty.

Cachix publication completed successfully for all ten provisioning builds by
17:04 UTC. A newly uploaded derivation was independently read from the public
cache. Publication uses only the qualified main jobset and retains failed
uploads for retry. The spool can be reconstructed by replaying successful
build notifications after recovery; token files must be reinstalled separately.

The provisioning PR passed its required GitHub gate, including the corrected
enrollment VM. A separate [readiness run](https://github.com/PseudoDesign/kaiba-provisioning/actions/runs/36335709462)
on a GitHub runner also passed: it reached public HTTPS with certificate
verification, evaluated main's ten derivations, and used the new waiter to check
all ten actual GitHub statuses and linked Hydra results. This confirms external
access despite public-address hairpin connections timing out inside the LAN.

The repository variable `HYDRA_MAIN_ENABLED=true` enables the new workflow's main
delegation after the approved provisioning PR is merged. PRs and manual runs
retain GitHub builders. Set the variable to `false` to restore GitHub main builds
for subsequent runs. Acceptance of the first delegated main run requires all ten
statuses for that exact revision, unchanged-build reuse, and a successful
required aggregate; the qualification run above is separate evidence.
