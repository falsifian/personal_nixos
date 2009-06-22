{pkgs, config, ...}:

let
  inherit (pkgs.lib) mkOption mergeOneOption mkIf filter optionalString any;
  cfg = config.services.xserver.desktopManager;

  # Whether desktop manager `d' is capable of setting a background.
  # If it isn't, the `feh' program is used as a fallback.
  needBGCond = d: ! (d ? bgSupport && d.bgSupport);
in

{
  require = [
    ./kde.nix
    ./kde4.nix
    ./gnome.nix
    ./xterm.nix
    ./none.nix
  ];

  services = {
    xserver = {
      displayManager = {
        session = cfg.session.list;
      };

      desktopManager = {
        session = mkOption {
          default = [];
          example = [{
            name = "kde";
            bgSupport = true;
            start = "...";
          }];
          description = "
            Internal option used to add some common line to desktop manager
            scripts before forwarding the value to the
            <varname>displayManager</varname>.
          ";
          apply = list: {
            list = map (d: d // {
              manage = "desktop";
              start = d.start
              + optionalString (needBGCond d) ''
                if test -e $HOME/.background-image; then
                  ${pkgs.feh}/bin/feh --bg-scale $HOME/.background-image
                fi
              '';
            }) list;
            needBGPackages = [] != filter needBGCond list;
          };
        };


        default = mkOption {
          default = "xterm";
          example = "none";
          description = "
            Default desktop manager loaded if none have been chosen.
          ";
          merge = mergeOneOption;
          apply = defaultDM:
            if any (w: w.name == defaultDM) cfg.session.list then
              defaultDM
            else
              throw "Default desktop manager ($(defaultDM)) not found.";
        };
      };
    };
  };

  environment = mkIf (config.services.xserver.enable && cfg.session.needBGPackages) {
    extraPackages = [ pkgs.feh ];
  };
}
