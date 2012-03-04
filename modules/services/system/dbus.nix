# D-Bus configuration and system bus daemon.

{ config, pkgs, ... }:

with pkgs.lib;

let

  cfg = config.services.dbus;

  homeDir = "/var/run/dbus";

  configDir = pkgs.stdenv.mkDerivation {
    name = "dbus-conf";
    buildCommand = ''
      ensureDir $out

      cp -v ${pkgs.dbus_daemon}/etc/dbus-1/system.conf $out/system.conf

      # !!! Hm, these `sed' calls are rather error-prone...

      # Tell the daemon where the setuid wrapper around
      # dbus-daemon-launch-helper lives.
      sed -i $out/system.conf \
          -e 's|<servicehelper>.*/libexec/dbus-daemon-launch-helper|<servicehelper>${config.security.wrapperDir}/dbus-daemon-launch-helper|'

      # Add the system-services and system.d directories to the system
      # bus search path.
      sed -i $out/system.conf \
          -e 's|<standard_system_servicedirs/>|${systemServiceDirs}|' \
          -e 's|<includedir>system.d</includedir>|${systemIncludeDirs}|'

      cp ${pkgs.dbus_daemon}/etc/dbus-1/session.conf $out/session.conf

      # Add the services and session.d directories to the session bus
      # search path.
      sed -i $out/session.conf \
          -e 's|<standard_session_servicedirs />|${sessionServiceDirs}&|' \
          -e 's|<includedir>session.d</includedir>|${sessionIncludeDirs}|'
    ''; # */
  };

  systemServiceDirs = concatMapStrings
    (d: "<servicedir>${d}/share/dbus-1/system-services</servicedir> ")
    cfg.packages;

  systemIncludeDirs = concatMapStrings
    (d: "<includedir>${d}/etc/dbus-1/system.d</includedir> ")
    cfg.packages;

  sessionServiceDirs = concatMapStrings
    (d: "<servicedir>${d}/share/dbus-1/services</servicedir> ")
    cfg.packages;

  sessionIncludeDirs = concatMapStrings
    (d: "<includedir>${d}/etc/dbus-1/session.d</includedir> ")
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

    environment.systemPackages = [ pkgs.dbus_daemon pkgs.dbus_tools ];

    environment.etc = singleton
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

    jobs.dbus =
      { startOn = "started udev and started syslogd";

        path = [ pkgs.dbus_daemon pkgs.dbus_tools ];

        preStart =
          ''
            mkdir -m 0755 -p ${homeDir}
            chown messagebus ${homeDir}

            mkdir -m 0755 -p /var/lib/dbus
            dbus-uuidgen --ensure

            rm -f ${homeDir}/pid
          '';

        daemonType = "fork";

        exec = "dbus-daemon --system";

        /*
        postStart =
          ''
            # Signal Upstart to connect to the system bus.  This
            # allows ‘initctl’ to work for non-root users.
            kill -USR1 1
          '';
        */

        postStop =
          ''
            # !!! Hack: doesn't belong here.
            pid=$(cat /var/run/ConsoleKit/pid || true)
            if test -n "$pid"; then
                kill $pid || true
                rm -f /var/run/ConsoleKit/pid
            fi
          '';
      };

    security.setuidOwners = singleton
      { program = "dbus-daemon-launch-helper";
        source = "${pkgs.dbus_daemon}/libexec/dbus-daemon-launch-helper";
        owner = "root";
        group = "messagebus";
        setuid = true;
        setgid = false;
        permissions = "u+rx,g+rx,o-rx";
      };

    services.dbus.packages =
      [ "/nix/var/nix/profiles/default"
        config.system.path
      ];

    environment.pathsToLink = [ "/etc/dbus-1" "/share/dbus-1" ];

  };

}
