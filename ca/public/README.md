# Public CA Artifacts

This directory is for public artifacts copied out of the offline CA working
directory with `nix run .#ca-install-public-artifacts`:

- `root_ca.crt`: public pseudo.design root CA certificate.
- `root_ca.fingerprint`: pinned root fingerprint used by device enrollment.

The private root key, provisioner key, passwords, enrollment tokens, and online
intermediate key material do not belong here.
