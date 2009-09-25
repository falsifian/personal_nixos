# This module declares the options to define a *display manager*, the
# program responsible for handling X logins (such as xdm, kdm, gdb, or
# SLiM).  The display manager allows the user to select a *session
# type*.  When the user logs in, the display manager starts the
# *session script* ("xsession" below) to launch the selected session
# type.  The session type defines two things: the *desktop manager*
# (e.g., KDE, Gnome or a plain xterm), and optionally the *window
# manager* (e.g. kwin or twm).

{ config, pkgs, ... }:

with pkgs.lib;

let

  cfg = config.services.xserver;
  xorg = pkgs.xorg;

  # file provided by services.xserver.displayManager.session.script
  xsession = wm: dm: pkgs.writeScript "xsession"
    ''
      #! /bin/sh

      # Handle being called by kdm.
      if test "''${1:0:1}" = /; then eval exec "$1"; fi

      # The first argument of this script is the session type.
      sessionType="$1"
      if test "$sessionType" = default; then sessionType=""; fi

      ${optionalString (!cfg.displayManager.job.logsXsession) ''
        exec > ~/.xsession-errors 2>&1
      ''}

      ${optionalString cfg.startSSHAgent ''
        if test -z "$SSH_AUTH_SOCK"; then
            # Restart this script as a child of the SSH agent.  (It is
            # also possible to start the agent as a child that prints
            # the required environment variabled on stdout, but in
            # that mode ssh-agent is not terminated when we log out.)
            export SSH_ASKPASS=${pkgs.x11_ssh_askpass}/libexec/x11-ssh-askpass
            exec ${pkgs.openssh}/bin/ssh-agent "$0" "$sessionType"
        fi
      ''}

      # Start a ConsoleKit session so that we get ownership of various
      # devices.
      if test -z "$XDG_SESSION_COOKIE"; then
          exec ${pkgs.consolekit}/bin/ck-launch-session "$0" "$sessionType"
      fi

      # Load X defaults.
      if test -e ~/.Xdefaults; then
          ${xorg.xrdb}/bin/xrdb -merge ~/.Xdefaults
      fi

      source /etc/profile

      # Allow the user to setup a custom session type.
      if test "$sessionType" = custom; then
          test -x ~/.xsession && exec ~/.xsession
          sessionType="" # fall-thru if there is no ~/.xsession
      fi

      # The session type is "<desktop-manager> + <window-manager>", so
      # extract those.
      windowManager="''${sessionType##* + }"
      : ''${windowManager:=${cfg.windowManager.default}}
      desktopManager="''${sessionType% + *}"
      : ''${desktopManager:=${cfg.desktopManager.default}}

      # Start the window manager.
      case $windowManager in
        ${concatMapStrings (s: ''
          (${s.name})
            ${s.start}
            ;;
        '') wm}
        (*) echo "$0: Window manager '$windowManager' not found.";;
      esac

      # Start the desktop manager.
      case $desktopManager in
        ${concatMapStrings (s: ''
          (${s.name})
            ${s.start}
            ;;
        '') dm}
        (*) echo "$0: Desktop manager '$desktopManager' not found.";;
      esac

      test -n "$waitPID" && wait "$waitPID"
      exit 0
    '';

  mkDesktops = names: pkgs.runCommand "desktops" {}
    ''
      ensureDir $out
      ${concatMapStrings (n: ''
        cat - > "$out/${n}.desktop" << EODESKTOP
        [Desktop Entry]
        Version=1.0
        Type=XSession
        TryExec=${cfg.displayManager.session.script}
        Exec=${cfg.displayManager.session.script} '${n}'
        Name=${n}
        Comment=
        EODESKTOP
      '') names}
    '';

in

{

  imports = [ ./kdm.nix ./slim.nix ];


  options = {

    services.xserver.displayManager = {

      xauthBin = mkOption {
        default = "${xorg.xauth}/bin/xauth";
        description = "Path to the <command>xauth</command> program used by display managers.";
      };

      xserverBin = mkOption {
        default = "${xorg.xorgserver}/bin/X";
        description = "Path to the X server used by display managers.";
      };

      xserverArgs = mkOption {
        default = [];
        example = [ "-ac" "-logverbose" "-nolisten tcp" ];
        description = "List of arguments for the X server.";
        apply = toString;
      };

      session = mkOption {
        default = [];
        example = [
          {
            manage = "desktop";
            name = "xterm";
            start = "
              ${pkgs.xterm}/bin/xterm -ls &
              waitPID=$!
            ";
          }
        ];
        description = ''
          List of sessions supported with the command used to start each
          session.  Each session script can set the
          <varname>waitPID</varname> shell variable to make this script
          wait until the end of the user session.  Each script is used
          to define either a windows manager or a desktop manager.  These
          can be differentiated by setting the attribute
          <varname>manage</varname> either to <literal>"window"</literal>
          or <literal>"desktop"</literal>.

          The list of desktop manager and window manager should appear
          inside the display manager with the desktop manager name
          followed by the window manager name.
        '';
        apply = list: rec {
          wm = filter (s: s.manage == "window") list;
          dm = filter (s: s.manage == "desktop") list;
          names = concatMap (d: map (w: d.name + " + " + w.name) wm) dm;
          desktops = mkDesktops names;
          script = xsession wm dm;
        };
      };

      job = mkOption {
        default = {};
        type = types.uniq types.optionSet;
        description = "This option defines how to start the display manager.";

        options = {
  
          preStart = mkOption {
            default = "";
            example = "rm -f /var/log/my-display-manager.log";
            description = "Script executed before the display manager is started.";
          };
         
          execCmd = mkOption {
            example = "${pkgs.slim}/bin/slim";
            description = "Command to start the display manager.";
          };
         
          environment = mkOption {
            default = {};
            example = { SLIM_CFGFILE = /etc/slim.conf; };
            description = "Additional environment variables needed by the display manager.";
          };
         
          logsXsession = mkOption {
            default = false;
            description = ''
              Whether the display manager redirects the
              output of the session script to
              <filename>~/.xsession-errors</filename>.
            '';
          };
         
        };
        
      };

    };
    
  };

}
