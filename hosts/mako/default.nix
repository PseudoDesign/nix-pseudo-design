{
  crtvar,
  dogsitting,
  pkgs,
  self,
  ...
}:

let
  pseudoDesignSite = self.packages.${pkgs.stdenv.hostPlatform.system}.pseudo-design-site;
in
{
  imports = [
    crtvar.nixosModules.default
    dogsitting.nixosModules.default
  ];

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
