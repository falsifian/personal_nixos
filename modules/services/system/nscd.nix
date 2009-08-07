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

    jobs = singleton
      { name = "nscd";

        description = "Name Service Cache Daemon";

        startOn = "startup";
        stopOn = "shutdown";

        environment = { LD_LIBRARY_PATH = nssModulesPath; };
        
        preStart =
          ''
            mkdir -m 0755 -p /var/run/nscd
            mkdir -m 0755 -p /var/db/nscd
          '';

        exec = "${pkgs.glibc}/sbin/nscd -f ${./nscd.conf} -d 2> /dev/null";
      };

  };
}
