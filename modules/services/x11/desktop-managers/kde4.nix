{ config, pkgs, ... }:

with pkgs.lib;

let

  xcfg = config.services.xserver;
  cfg = xcfg.desktopManager.kde4;
  xorg = pkgs.xorg;

in

{

  imports = [ ./kde-environment.nix ];

    
  options = {

    services.xserver.desktopManager.kde4.enable = mkOption {
      default = false;
      example = true;
      description = "Enable the KDE 4 desktop environment.";
    };

  };

  
  config = mkIf (xcfg.enable && cfg.enable) {

    # If KDE 4 is enabled, make it the default desktop manager (unless
    # overriden by the user's configuration).
    # !!! doesn't work yet ("Multiple definitions. Only one is allowed
    # for this option.")
    # services.xserver.desktopManager.default = mkOverride 900 "kde4";

    services.xserver.desktopManager.session = singleton
      { name = "kde4";
        bgSupport = true;
        start =
          ''
            # Start KDE.
            exec ${pkgs.kde43.kdebase_workspace}/bin/startkde
          '';
      };

    security.setuidPrograms = [ "kcheckpass" ];

    environment.kdePackages =
      [ pkgs.kde43.kdelibs
        pkgs.kde43.kdebase
        pkgs.kde43.kdebase_runtime
        pkgs.kde43.kdebase_workspace
	pkgs.kde43.oxygen_icons
        pkgs.shared_mime_info
      ];

    environment.x11Packages =
      [ xorg.xmessage # so that startkde can show error messages
        pkgs.qt4 # needed for qdbus
        xorg.xset # used by startkde, non-essential
      ];

    environment.etc = singleton
      { source = "${pkgs.xkeyboard_config}/etc/X11/xkb";
        target = "X11/xkb";
      };

  };

}
