# Configuration for the pwdutils suite of tools: passwd, useradd, etc.

{config, pkgs, ...}:

let

  loginDefs =
    ''
      DEFAULT_HOME yes

      SYS_UID_MIN  100
      SYS_UID_MAX  499
      UID_MIN      1000
      UID_MAX      29999

      SYS_GID_MIN  100
      SYS_GID_MAX  499
      GID_MIN      1000
      GID_MAX      29999

      TTYGROUP     tty
      TTYPERM      0620

      # Uncomment this to allow non-root users to change their account
      #information.  This should be made configurable.
      #CHFN_RESTRICT frwh
    '';

in

{

  ###### interface
  
  options = {

    users.defaultUserShell = pkgs.lib.mkOption {
      default = "/var/run/current-system/sw/bin/bash";
      description = ''
        This option defined the default shell assigned to user
        accounts.  This must not be a store path, since the path is
        used outside the store (in particular in /etc/passwd).
        Rather, it should be the path of a symlink that points to the
        actual shell in the Nix store.
      '';
    };
  
  };

  
  ###### implementation

  config = {

    environment.systemPackages = [ pkgs.shadow ];

    environment.etc =
      [ { # /etc/login.defs: global configuration for pwdutils.  You
          # cannot login without it! 
          source = pkgs.writeText "login.defs" loginDefs;
          target = "login.defs";
        } 

        { # /etc/default/useradd: configuration for useradd.
          source = pkgs.writeText "useradd"
            ''
              GROUP=100
              HOME=/home
              SHELL=${config.users.defaultUserShell}
            '';
          target = "default/useradd";
        }
      ];

    security.pam.services =
      [ { name = "chsh"; rootOK = true; }
        { name = "chfn"; rootOK = true; }
        # Enable ‘ownDevices’ for the services/x11/display-managers/auto.nix module.
        { name = "su"; rootOK = true; ownDevices = true; forwardXAuth = true; }
        { name = "passwd"; }
        # Note: useradd, groupadd etc. aren't setuid root, so it
        # doesn't really matter what the PAM config says as long as it
        # lets root in.
        { name = "useradd"; rootOK = true; }
        { name = "usermod"; rootOK = true; }
        { name = "userdel"; rootOK = true; }
        { name = "groupadd"; rootOK = true; }
        { name = "groupmod"; rootOK = true; } 
        { name = "groupmems"; rootOK = true; }
        { name = "groupdel"; rootOK = true; }
        { name = "login"; ownDevices = true; allowNullPassword = true; }
      ];
      
    security.setuidPrograms = [ "passwd" "chfn" "su" ];
    
  };
  
}
