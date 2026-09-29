{
  config,
  kaiba-dns,
  kaiba-fleet,
  lib,
  ...
}:
let
  cfg = config.kaiba.lanQualification;
  identityPkgs = import kaiba-fleet.inputs.nixpkgs { system = "aarch64-linux"; };
  dnsPackage = kaiba-dns.packages.aarch64-linux.dns-suite;
  domain = "pilot.kaiba.pseudo.design";
  socket = "unix:///run/kaiba/identity/local/public/api.sock";
in
{
  imports = [ kaiba-dns.nixosModules.lan-qualification ];

  # Deliberately disabled until the station bridge, current pilot admission,
  # narrow SPIRE registrations and operator grant have been reviewed/prepared.
  config = lib.mkMerge [
    { kaiba.lanQualification.enable = lib.mkDefault false; }
    (lib.mkIf cfg.enable {
      services.kaiba.identity = {
        role = "server";
        serverListenAddress = "192.168.8.214";
        openFirewall = false;
        pilot.agentAddresses = [ "192.168.8.249" ];
      };
      kaiba.lanQualification = {
        zone = domain;
        listenAddress = "192.168.8.214";
        allowedPeers = [ "192.168.8.249" ];
        knotPackage = identityPkgs.knot-dns;
      };
      kaiba.deviceAgent = {
        package = dnsPackage;
        identity = {
          workloadAPISocket = socket;
          controllerSPIFFEID = "spiffe://${domain}/service/dns-controller";
        };
      };
      kaiba.updateController = {
        controller.package = dnsPackage;
        publisher.package = dnsPackage;
        identity = {
          workloadAPISocket = socket;
          trustDomain = domain;
          fleetAuthorizationURL = "https://192.168.8.249:18446";
          fleetServerSPIFFEID = "spiffe://${domain}/service/workload-registry";
        };
      };
      systemd.services.kaiba-agent = {
        requires = [ "spire-agent.service" ];
        after = [ "spire-agent.service" ];
      };
      systemd.services.kaiba-controller = {
        requires = [ "spire-agent.service" ];
        after = [ "spire-agent.service" ];
      };
    })
  ];
}
