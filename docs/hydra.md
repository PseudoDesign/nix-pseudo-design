# Hydra host integration

The pinned `kaiba-infra` flake supplies the Hydra, HTTPS proxy and restricted
backup receiver modules. Ace imports Hydra alongside its existing pilot
credential-persistence module and a hardware module preserving its installed
partition labels, mounts and legacy disk-unlock recipe. Mako adds the
`hydra.pseudo.design` virtual host and backup receiver alongside its existing
services. It also enables the same pilot-persistence module with its existing
UID 991/GID 985; Ace retains UID 994/GID 988. Neither host initializes or replaces
the enrolled credential.

The reserved LAN addresses are Ace `192.168.8.214` and Mako `192.168.8.247`.
Ace permits Hydra's port 3000 only from Mako. Mako uses the existing ACME contact
and HTTPS ingress. Keep the DHCP reservations aligned with these addresses.

Run the infrastructure qualification and operational procedure from
`kaiba-infra/docs/hydra-on-ace.md`, including the backup SSH credential setup.
The backup private key remains on Ace; Mako receives its public key only.

The native ARM64 KVM smoke test passed on Ace on 2026-09-27 UTC while running
kernel 6.12.47 and generation
`/nix/store/n4z60a804j4irva6qjy46qh0bdq3pl2v-nixos-system-ace-25.11.20260313.3e20095`.
Requalify after a kernel/virtualization change. This test does not validate a
NixOS system upgrade or the real device's disk-unlock boot path.

At implementation time, the repository's Ace candidate uses NixOS 26.05 and
kernel 6.18.42, while the running device uses NixOS 25.11 and kernel 6.12.47.
Review the complete closure difference and recovery procedure before activation,
as required by [Ace's persistence deployment notes](ace-pilot-persistence.md).
Do not use `nixos-anywhere`, change the enrolled pilot identity, or enable swap.

The ordinary deployment order is: publish the infrastructure revision, lock it
here and in provisioning, build host closures, review their differences, test
Mako and Ace configurations, verify HTTPS and the small infrastructure job,
then persist the host generations and enable provisioning after qualification.

See the [concrete deployment review](hydra-deployment-review.md) for measured
qualification, closure differences, preserved storage and the remaining
OS-upgrade and recovery decision.

The [test deployment report](hydra-test-deployment.md) records the running Hydra
service, first successful infrastructure build, restored backup and firmware
correction required before persistent switching and reboot.
