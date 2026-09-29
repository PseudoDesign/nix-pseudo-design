{ kaiba-infra, lib, ... }:
let
  trust = builtins.fromJSON (builtins.readFile ../../hosts/human-access-trust.json);
in {
  imports = [ kaiba-infra.nixosModules.ssh-human-access ];
  # Remain disabled until the initial owner's actual immutable subject has
  # been read from Keycloak and reviewed. Enrollment separately gates issuance.
  services.kaibaHumanSSH = {
    enable = trust.ownerSubject != null;
    trustedUserCAKeys = [ trust.sshUserCA ];
    authorizedPrincipals = lib.optionalAttrs (trust.ownerSubject != null) {
      adam = [ "kaiba:person:${trust.ownerSubject}" ];
    };
  };
}
