# D-Bus system-wide daemon.
{pkgs, config, ...}:

with pkgs.lib;

let

  cfg = config.services.dbus;

  # !!! dbus_temp uses /etc/dbus-1; will be merged into pkgs.dbus later.
  dbus = pkgs.dbus_temp;

  homeDir = "/var/run/dbus";

  configDir = pkgs.stdenv.mkDerivation {
    name = "dbus-conf";
    buildCommand = ''
      ensureDir $out
      
      cp ${dbus}/etc/dbus-1/system.conf $out/system.conf

      # Tell the daemon where the setuid wrapper around
      # dbus-daemon-launch-helper lives.      
      sed -i $out/system.conf \
          -e 's|<servicehelper>.*/libexec/dbus-daemon-launch-helper|<servicehelper>${config.security.wrapperDir}/dbus-daemon-launch-helper|'

      # Add the system-services directories to the daemon's search path.
      sed -i $out/system.conf \
          -e 's|<standard_system_servicedirs/>|${systemServiceDirs}|'
          
      # Note: system.conf includes ./system.d (i.e. it has a relative,
      # not absolute path).
      ensureDir $out/system.d
      for i in ${toString cfg.packages}; do
        ln -s $i/etc/dbus-1/system.d/* $out/system.d/
      done
    ''; # */
  };

  systemServiceDirs = concatMapStrings
    (d: "<servicedir>${d}/share/dbus-1/system-services</servicedir> ")
    cfg.packages;

in

{

  ###### interface

  options = {
  
    services.dbus = {

      enable = mkOption {
        default = true;
        description = ''
          Whether to start the D-Bus message bus daemon, which is
          required by many other system services and applications.
        '';
        merge = pkgs.lib.mergeEnableOption;
      };

      packages = mkOption {
        default = [];
        description = ''
          Packages whose D-Bus configuration files should be included in
          the configuration of the D-Bus system-wide message bus.
          Specifically, every file in
          <filename><replaceable>pkg</replaceable>/etc/dbus-1/system.d</filename>
          is included.
        '';
      };

    };
    
  };


  ###### implementation

  config = mkIf cfg.enable {

    environment.systemPackages = [dbus.daemon dbus.tools];

    environment.etc = singleton
      # We need /etc/dbus-1/system.conf for now, because
      # dbus-daemon-launch-helper is called with an empty environment
      # and no arguments.  So we have no way to tell it the location
      # of our config file.
      { source = configDir;
        target = "dbus-1";
      };

    users.extraUsers = singleton
      { name = "messagebus";
        uid = config.ids.uids.messagebus;
        description = "D-Bus system message bus daemon user";
        home = homeDir;
        group = "messagebus";
      };

    users.extraGroups = singleton
      { name = "messagebus";
        gid = config.ids.gids.messagebus;
      };

    jobs = singleton
      { name = "dbus";

        startOn = "startup";
        stopOn = "shutdown";

        preStart =
          ''
            mkdir -m 0755 -p ${homeDir}
            chown messagebus ${homeDir}

            mkdir -m 0755 -p /var/lib/dbus
            ${dbus.tools}/bin/dbus-uuidgen --ensure
 
            rm -f ${homeDir}/pid
            # !!! hack - dbus should be running once this job is
            # considered "running"; should be fixable once we have
            # Upstart 0.6.
            ${dbus}/bin/dbus-daemon --config-file=${configDir}/system.conf
          '';

        postStop =
          ''
            pid=$(cat ${homeDir}/pid)
            if test -n "$pid"; then
                kill -9 $pid
            fi
          '';
      };

    security.setuidOwners = singleton
      { program = "dbus-daemon-launch-helper";
        source = "${dbus}/libexec/dbus-daemon-launch-helper";
        owner = "root";
        group = "messagebus";
        setuid = true;
        setgid = false;
        permissions = "u+rx,g+rx,o-rx";
      };

  };
 
}
