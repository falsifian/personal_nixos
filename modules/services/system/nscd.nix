{pkgs, config, ...}:

let

  nssModulesPath = config.system.nssModules.path;

  inherit (pkgs.lib) singleton;
  
in

{
  config = {
  
    users.extraUsers = singleton
      { name = "nscd";
        uid = config.ids.uids.nscd;
        description = "Name service cache daemon user";
      };

    jobs = singleton {
      name = "nscd";
        
      job = ''
        description \"Name Service Cache Daemon\"

        start on startup
        stop on shutdown

        env LD_LIBRARY_PATH=${nssModulesPath}

        start script

            mkdir -m 0755 -p /var/run/nscd
            mkdir -m 0755 -p /var/db/nscd

            rm -f /var/db/nscd/* # for testing

        end script

        # !!! -d turns on debug info which probably makes nscd slower
        # 2>/dev/null is to make it shut up
        respawn ${pkgs.glibc}/sbin/nscd -f ${./nscd.conf} -d 2> /dev/null
      '';
    };

  };
}
