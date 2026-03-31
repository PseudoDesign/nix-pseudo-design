{ pkgs, config, lib,  ... }: 
let
  secretsDirectory = "/run/secrets";
  luksKeyFile = "${secretsDirectory}/luks.key";
  luksKeySalt = "some-test-salt";
  cfg = config.rpiOtpLuksKey;
in
{

  options = {
    rpiOtpLuksKey.enable = lib.mkEnableOption "Raspberry Pi OTP LUKS Key";
  };


  config = lib.mkIf cfg.enable {
    # The service that places our key into the rootfs is needed on boot
    # necessitating the need for boot.initrd.systemd
    boot.initrd.systemd.enable = true; 
    boot.initrd.systemd.services.rpi-otp-luks-key-initrd = {
      wantedBy = [ "initrd.target" ];
      before = [
        "cryptsetup.target"
      ];
      unitConfig.DefaultDependencies = false;
          description = "Get the luks key from Raspberry Pi OTP.";
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        install -d -m 0700 '${secretsDirectory}'
        ${pkgs.rpi-otp-luks-key}/bin/rpi-otp-luks-key ${luksKeySalt} > '${luksKeyFile}'
        chmod 600 '${luksKeyFile}'
      '';
    };

    # IDK if this is actually necessary?  Typically you don't need to call 
    # out dependencies like this explicitly.
    # Maybe now that I cleaned up the package feed, we can get rid of this.
    boot.initrd.systemd.extraBin = {
      rpi-otp-luks-key = "${pkgs.rpi-otp-luks-key}/bin/rpi-otp-luks-key";
      rpi-otp-private-key = "${pkgs.rpi-otp-private-key}/bin/rpi-otp-private-key";
      vcgencmd = "${pkgs.libraspberrypi}/bin/vcgencmd";
      vcmailbox = "${pkgs.libraspberrypi}/bin/vcmailbox";
      awk = "${pkgs.gawk}/bin/awk";
      sed = "${pkgs.gnused}/bin/sed";
      grep = "${pkgs.gnugrep}/bin/grep";
      which = "${pkgs.which}/bin/which";
      xxd = "${pkgs.xxd}/bin/xxd";
    };
  };
}