{config, pkgs, ...}:

with pkgs.lib;

let

  inherit (pkgs) pam_usb;

  cfg = config.security.pam.usb;

  anyUsbAuth = any (attrByPath ["usbAuth"] false) config.security.pam.services;

in

{
  options = {

    security.pam.usb = {
      enable = mkOption {
        default = false;
        description = ''
          Enable USB login for all login system unless the service disabled
          it.  For more information, visit <link
          xlink:href="http://pamusb.org/doc/quickstart#setting_up" />.
        '';
      };

    };

  };

  config = mkIf (cfg.enable || anyUsbAuth) {

    # pmount need to have a set-uid bit to make pam_usb works in user
    # environment. (like su, sudo)

    security.setuidPrograms = [ "pmount" "pumount" ];
    environment.systemPackages = [ pkgs.pmount ];

  };
}
