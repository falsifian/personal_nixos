{pkgs, config, ...}:

let
  inherit (pkgs.lib) mkOption mkIf;
  cfg = config.services.xserver.windowManager.xmonad;
in

{
  services = {
    xserver = {

      windowManager = {
        xmonad = {
          enable = mkOption {
            default = false;
            example = true;
            description = "Enable the xmonad window manager.";
          };
        };

        session = mkIf cfg.enable [{
          name = "xmonad";
          start = "
            ${pkgs.xmonad}/bin/xmonad &
            waitPID=$!
          ";
        }];
      };

    };
  };
}
