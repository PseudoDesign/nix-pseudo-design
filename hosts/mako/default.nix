{
  networking = {
    hostName = "mako";
    firewall.allowedTCPPorts = [
      80
      443
    ];
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "admin@pseudo.design";
  };

  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedTlsSettings = true;

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
