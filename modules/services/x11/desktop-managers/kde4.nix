{ config, pkgs, ... }:

with pkgs.lib;

let

  xcfg = config.services.xserver;
  cfg = xcfg.desktopManager.kde4;
  xorg = pkgs.xorg;

in

{
  options = {

    services.xserver.desktopManager.kde4.enable = mkOption {
      default = false;
      example = true;
      description = "Enable the KDE 4 desktop environment.";
    };

    environment.kdePackages = mkOption {
      default = [];
      example = [ pkgs.kde4.kdesdk ];
      type = types.list types.package;
      description = "This option is obsolete.  Please use <option>environment.systemPackages</option> instead.";
    };

  };

  
  config = mkIf (xcfg.enable && cfg.enable) {

    # If KDE 4 is enabled, make it the default desktop manager (unless
    # overriden by the user's configuration).
    # !!! doesn't work yet ("Multiple definitions. Only one is allowed
    # for this option.")
    # services.xserver.desktopManager.default = mkOverrideTemplate 900 "kde4";

    services.xserver.desktopManager.session = singleton
      { name = "kde4";
        bgSupport = true;
        start =
          ''
            # Start KDE.
            exec ${pkgs.kde4.kdebase_workspace}/bin/startkde
          '';
      };

    security.setuidOwners = [ {
      program = "kcheckpass";
      source = "${pkgs.kde4.kdebase_workspace}/lib/kde4/libexec/kcheckpass";
      owner = "root";
      group = "root";
      setuid = true;
    } ];

    environment = {
      systemPackages = [
        # temporary workarounds
        pkgs.shared_desktop_ontologies 
        pkgs.kde4.strigi

        pkgs.kde4.kdelibs
        pkgs.kde4.kdebase
        pkgs.kde4.kdebase_runtime
        pkgs.kde4.kdebase_workspace
        pkgs.kde4.oxygen_icons
        pkgs.kde4.qt4 # needed for qdbus
        pkgs.shared_mime_info
        pkgs.gst_all.gstreamer
        pkgs.gst_all.gstPluginsBase
        pkgs.gst_all.gstPluginsGood
        pkgs.gst_all.gstFfmpeg # for mp3 playback
        xorg.xmessage # so that startkde can show error messages
        xorg.xset # used by startkde, non-essential
      ] ++ config.environment.kdePackages;

      pathsToLink = [ "/share" ];

      etc = singleton
      { source = "${pkgs.xkeyboard_config}/etc/X11/xkb";
        target = "X11/xkb";
      };
    };
  };

}
