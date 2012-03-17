{ config, pkgs, ... }:

with pkgs.lib;

let

  uid = config.ids.uids.portmap;
  gid = config.ids.gids.portmap;

  portmap = pkgs.portmap.override { daemonUID = uid; daemonGID = gid; };

in

{

  ###### interface

  options = {

    services.portmap = {

      enable = mkOption {
        default = false;
        description = ''
          Whether to enable `portmap', an ONC RPC directory service
          notably used by NFS and NIS, and which can be queried
          using the rpcinfo(1) command.
        '';
      };

      verbose = mkOption {
        default = false;
        description = ''
          Whether to enable verbose output.
        '';
      };

      chroot = mkOption {
        default = "/var/empty";
        description = ''
          If non-empty, a path to change root to.
        '';
      };

    };

  };


  ###### implementation

  config = mkIf config.services.portmap.enable {

    environment.systemPackages = [ portmap ];

    users.extraUsers = singleton
      { name = "portmap";
        inherit uid;
        description = "Portmap daemon user";
        home = "/var/empty";
      };

    users.extraGroups = singleton
      { name = "portmap";
        inherit gid;
      };

    jobs.portmap =
      { description = "ONC RPC portmap";

        startOn = "started network-interfaces";
        stopOn = "never";

        daemonType = "fork"; # needed during shutdown

        path = [ portmap pkgs.netcat ];

        exec =
          ''
            portmap \
              ${optionalString (config.services.portmap.chroot != "")
                "-t '${config.services.portmap.chroot}'"} \
              ${if config.services.portmap.verbose then "-v" else ""}
          '';

        postStart =
          ''
            # Portmap forks into the background before it starts
            # listening, so wait until its ready.
            while ! nc -z localhost 111; do
                if [[ "$(status)" =~ stop/ ]]; then exit; fi
                sleep 1
            done
          '';
      };

  };

}
