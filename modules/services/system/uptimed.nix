{pkgs, config, ...}:

let

  inherit (pkgs.lib) mkOption mkIf singleton;

  inherit (pkgs) uptimed;

  stateDir = "/var/spool/uptimed";

  uptimedUser = "uptimed";

  modprobe = config.system.sbin.modprobe;

  uptimedFlags = "";

in

{

  ###### interface
  
  options = {
  
    services.uptimed = {

      enable = mkOption {
        default = false;
        description = ''
          Uptimed allows you to track your highest uptimes.
        '';
      };

    };

  };


  ###### implementation

  config = mkIf config.services.uptimed.enable {
    environment.systemPackages = [ uptimed ];
  
    users.extraUsers = singleton
      { name = uptimedUser;
        uid = config.ids.uids.uptimed;
        description = "Uptimed daemon user";
        home = stateDir;
      };

    jobs = singleton {

      name = "uptimed";
      
      job = ''
        description "Uptimed daemon"

        start on startup
        stop on shutdown

        start script

            mkdir -m 0755 -p ${stateDir}
            chown ${uptimedUser} ${stateDir}

            # Needed to run uptimed as an unprivileged user.
            ${modprobe}/sbin/modprobe capability || true

            if ! test -f ${stateDir}/bootid ; then
              ${uptimed}/sbin/uptimed -b
            fi

        end script

        respawn ${uptimed}/sbin/uptimed ${uptimedFlags}
      '';

    };
    
  };
  
}
