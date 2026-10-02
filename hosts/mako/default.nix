{
  crtvar,
  dogsitting,
  kaiba-infra,
  pkgs,
  self,
  ...
}:

let
  pseudoDesignSite = self.packages.${pkgs.stdenv.hostPlatform.system}.pseudo-design-site;
  humanAccessTrust = builtins.fromJSON (builtins.readFile ../human-access-trust.json);
in
{
  imports = [
    ../../modules/services/kaiba-pilot-device.nix
    ../../modules/services/kaiba-human-access.nix
    ./pilot-agent.nix
    crtvar.nixosModules.default
    dogsitting.nixosModules.default
    kaiba-infra.nixosModules.hydra-proxy
    kaiba-infra.nixosModules.hydra-backup-receiver
    kaiba-infra.nixosModules.human-identity
    kaiba-infra.nixosModules.ssh-user-ca
    kaiba-infra.nixosModules.human-access-backup
    kaiba-infra.nixosModules.forgejo
  ];

  networking = {
    hostName = "mako";
    firewall.allowedTCPPorts = [
      80
      443
    ];
  };

  time.timeZone = "America/Indiana/Indianapolis";

  # Pi firmware's DTB supplies cgroup_disable=memory. The later generation
  # argument re-enables it so the identity services' memory limits take effect.
  boot.kernelParams = [ "cgroup_enable=memory" ];

  services.kaibaHydraProxy = {
    enable = true;
    upstream = "192.168.8.214:3000";
  };
  services.kaibaHydraBackupReceiver.enable = true;

  services.kaibaForgejo = {
    enable = true;
    package = kaiba-infra.packages.aarch64-linux.forgejo;
    # Imported workflows remain inert until runner and CI qualification passes.
    actionsEnable = false;
    sso = {
      enable = true;
      inherit (humanAccessTrust) ownerSubject;
    };
    backup = {
      enable = true;
      recipients = humanAccessTrust.backupRecipients;
    };
  };

  services.kaibaHumanIdentity = {
    enable = true;
    domain = "auth.pseudo.design";
    bootstrapAdminPasswordFile = "/var/lib/kaiba-human-identity/bootstrap-admin-password";
    javaHeapMB = 384;
    memoryHighMB = 768;
    memoryMaxMB = 1024;
  };
  services.kaibaSSHUserCA.enable = true;
  systemd.services.kaiba-ssh-ca = {
    after = [
      "nginx.service"
      "kaiba-human-identity-configure.service"
    ];
    requires = [ "kaiba-human-identity-configure.service" ];
    partOf = [ "kaiba-human-identity-configure.service" ];
  };
  services.kaibaHumanAccessBackup = {
    enable = true;
    # Encryption recipients are reviewed separately from future SSH key grants.
    recipients = humanAccessTrust.backupRecipients;
    receiverHost = "192.168.8.214";
  };
  # Server-to-server OIDC and CA traffic stays local while preserving the
  # public HTTPS names and certificate verification.
  networking.hosts."127.0.0.1" = [
    "auth.pseudo.design"
    "ssh-ca.pseudo.design"
    "git.pseudo.design"
    "docs.kaiba.pseudo.design"
  ];

  services.kaibaPilotDevice = {
    enable = true;
    # Preserve the IDs that own Mako's existing enrolled key.
    uid = 991;
    gid = 985;
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "admin@pseudo.design";
  };

  services.dogsitting = {
    enable = true;
    package = dogsitting.packages.${pkgs.stdenv.hostPlatform.system}.dogsitting;
    port = 9080;

    initialAdmin.passwordFile = "/run/keys/dogsitting-admin-password";

    production = {
      enable = true;
      hostName = "dogsitting.pseudo.design";
    };
  };

  services.crtvar = {
    enable = true;
    package = crtvar.packages.${pkgs.stdenv.hostPlatform.system}.crtvar;
    hostName = "crtvar.pseudo.design";
    enableACME = true;
    forceSSL = true;
  };

  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    virtualHosts."code.pseudo.design" = {
      enableACME = true;
      forceSSL = true;

      locations."/" = {
        proxyPass = "http://192.168.8.249:1785";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_read_timeout 3600;
          proxy_send_timeout 3600;
          proxy_buffering off;
        '';
      };

      extraConfig = ''
        ssl_client_certificate /var/lib/nginx-mtls/code-server-client-ca.pem;
        ssl_verify_client on;
        ssl_verify_depth 2;

        add_header Strict-Transport-Security "max-age=31536000" always;
      '';
    };

    virtualHosts."pseudo.design" = {
      root = pseudoDesignSite;
      serverAliases = [ "www.pseudo.design" ];
      enableACME = true;
      forceSSL = true;

      locations."/".tryFiles = "$uri $uri/ =404";

      extraConfig = ''
        error_page 404 /404.html;

        add_header Strict-Transport-Security "max-age=31536000" always;
        add_header Content-Security-Policy "default-src 'none'; base-uri 'none'; child-src 'none'; connect-src 'none'; font-src 'self'; form-action 'none'; frame-ancestors 'none'; frame-src 'none'; img-src 'self'; media-src 'none'; object-src 'none'; script-src 'none'; style-src 'self'; worker-src 'none'; upgrade-insecure-requests" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header X-Frame-Options "DENY" always;
        add_header Permissions-Policy "accelerometer=(), autoplay=(), camera=(), display-capture=(), encrypted-media=(), fullscreen=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), midi=(), payment=(), picture-in-picture=(), publickey-credentials-get=(), screen-wake-lock=(), usb=(), web-share=(), xr-spatial-tracking=()" always;
      '';
    };
  };
}
