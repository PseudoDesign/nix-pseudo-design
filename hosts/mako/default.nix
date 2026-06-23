{ dogsitting, pkgs, ... }:

{
  imports = [ dogsitting.nixosModules.default ];

  networking = {
    hostName = "mako";
    firewall.allowedTCPPorts = [
      80
      443
    ];
  };

  time.timeZone = "America/Indiana/Indianapolis";

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
      root = ./site;
      serverAliases = [ "www.pseudo.design" ];
      enableACME = true;
      forceSSL = true;

      locations."/".tryFiles = "$uri $uri/ =404";

      extraConfig = ''
        add_header Strict-Transport-Security "max-age=31536000" always;
        add_header Content-Security-Policy "default-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'; style-src 'self'; img-src 'self'; object-src 'none'; script-src 'none'; upgrade-insecure-requests" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header X-Frame-Options "DENY" always;
      '';
    };
  };
}
