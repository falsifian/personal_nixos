# Zabbix server daemon.
{ config, pkgs, ... }:

with pkgs.lib;

let

  cfg = config.services.zabbixServer;

  stateDir = "/var/run/zabbix";

  logDir = "/var/log/zabbix";

  libDir = "/var/lib/zabbix";

  pidFile = "${stateDir}/zabbix_server.pid";

  configFile = pkgs.writeText "zabbix_server.conf"
    ''
      LogFile = ${logDir}/zabbix_server

      PidFile = ${pidFile}

      ${optionalString (cfg.dbServer != "localhost") ''
        DBHost = ${cfg.dbServer}
      ''}

      DBName = zabbix

      DBUser = zabbix

      ${optionalString (cfg.dbPassword != "") ''
        DBPassword = ${cfg.dbPassword}
      ''}
    '';

in

{

  ###### interface

  options = {

    services.zabbixServer.enable = mkOption {
      default = false;
      description = ''
        Whether to run the Zabbix server on this machine.
      '';
    };

    services.zabbixServer.dbServer = mkOption {
      default = "localhost";
      description = "Hostname or IP address of the database server.";
    };

    services.zabbixServer.dbPassword = mkOption {
      default = "";
      description = "Password used to connect to the database server.";
    };

  };

  ###### implementation

  config = mkIf cfg.enable {

    services.postgresql.enable = cfg.dbServer == "localhost";

    users.extraUsers = singleton
      { name = "zabbix";
        uid = config.ids.uids.zabbix;
        description = "Zabbix daemon user";
      };

    jobs.zabbix_server =
      { name = "zabbix-server";

        description = "Zabbix server daemon";

        startOn = "filesystem";

        preStart =
          ''
            mkdir -m 0755 -p ${stateDir} ${logDir} ${libDir}
            chown zabbix ${stateDir} ${logDir} ${libDir}

            if ! test -e "${libDir}/db-created"; then
                ${pkgs.postgresql}/bin/createuser --no-superuser --no-createdb --no-createrole zabbix || true
                ${pkgs.postgresql}/bin/createdb --owner zabbix zabbix || true
                cat ${pkgs.zabbix.server}/share/zabbix/db/schema/postgresql.sql | ${pkgs.su}/bin/su -s "$SHELL" zabbix -c '${pkgs.postgresql}/bin/psql zabbix'
                cat ${pkgs.zabbix.server}/share/zabbix/db/data/data.sql | ${pkgs.su}/bin/su -s "$SHELL" zabbix -c '${pkgs.postgresql}/bin/psql zabbix'
                cat ${pkgs.zabbix.server}/share/zabbix/db/data/images_pgsql.sql | ${pkgs.su}/bin/su -s "$SHELL" zabbix -c '${pkgs.postgresql}/bin/psql zabbix'
                touch "${libDir}/db-created"
            fi
          '';

        path = [ pkgs.nettools pkgs.zabbix.server ];

        # Zabbix doesn't have an option not to daemonize, and doesn't
        # daemonize in a way that allows Upstart to track it.  So to
        # make sure that we notice when it goes down, we start Zabbix
        # with an open connection to a fifo, with a `cat' on the other
        # side.  If Zabbix dies, then `cat' will exit as well, so we
        # just monitor `cat'.
        script =
          ''
            rm -f ${stateDir}/dummy
            mkfifo ${stateDir}/dummy
            cat ${stateDir}/dummy &
            pid=$!
            zabbix_server --config ${configFile} 100>${stateDir}/dummy
            wait "$pid"
          '';

        postStop =
          ''
            pid=$(cat ${pidFile} 2> /dev/null || true)
            (test -n "$pid" && kill "$pid") || true
            # Wait until they're really gone.
            while ${pkgs.procps}/bin/pkill -u zabbix zabbix_server; do true; done
          '';
      };

  };

}
