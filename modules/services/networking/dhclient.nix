{pkgs, config, ...}:

let
  inherit (pkgs.lib) mkOption mkIf mergeEnableOption mergeListOption;

  inherit (pkgs) nettools dhcp lib;

  # Don't start dhclient on explicitly configured interfaces.
  ignoredInterfaces = ["lo"] ++
    map (i: i.name) (lib.filter (i: i ? ipAddress) config.networking.interfaces);

  stateDir = "/var/lib/dhcp"; # Don't use /var/state/dhcp; not FHS-compliant.

  dhclientExitHooks = pkgs.writeText "dhclient-exit-hooks"
    ''
      echo "$reason" >> /tmp/dhcp-exit
      echo "$exit_status" >> /tmp/dhcp-exit

      if test "$reason" = BOUND -o "$reason" = REBOOT; then
          ${pkgs.glibc}/sbin/nscd --invalidate hosts

          # Restart ntpd.  (The "ip-up" event below will trigger the
          # restart.)  We need to restart it to make sure that it will
          # actually do something: if ntpd cannot resolve the server
          # hostnames in its config file, then it will never do
          # anything ever again ("couldn't resolve ..., giving up on
          # it"), so we silently lose time synchronisation.
          ${pkgs.upstart}/sbin/initctl stop ntpd
          
          ${pkgs.upstart}/sbin/initctl emit ip-up
      fi

      if test "$reason" = EXPIRE -o "$reason" = RELEASE; then
          ${pkgs.upstart}/sbin/initctl emit ip-down
      fi
    '';
  
in

{

  ###### interface

  options = {
  
    networking.useDHCP = mkOption {
      default = true;
      merge = mergeEnableOption;
      description = "
        Whether to use DHCP to obtain an IP adress and other
        configuration for all network interfaces that are not manually
        configured.
      ";
    };
  
    networking.interfaces = mkOption {
      default = [];
      merge = mergeListOption;
      example = [
        { name = "eth0";
          ipAddress = "131.211.84.78";
          subnetMask = "255.255.255.128";
        }
      ];
      description = "
        The configuration for each network interface.  If
        <option>networking.useDHCP</option> is true, then each interface
        not listed here will be configured using DHCP.
      ";
    };

  };


  ###### implementation
  
  config = mkIf config.networking.useDHCP {

    jobs = pkgs.lib.singleton {
      name = "dhclient";

      job = ''
        description "DHCP client"

        start on network-interfaces/started
        stop on network-interfaces/stop

        env PATH_DHCLIENT_SCRIPT=${dhcp}/sbin/dhclient-script

        script
            export PATH=${nettools}/sbin:$PATH

            # Determine the interface on which to start dhclient.
            interfaces=

            for i in $(cd /sys/class/net && ls -d *); do
                if ! for j in ${toString ignoredInterfaces}; do echo $j; done | grep -F -x -q "$i"; then
                    echo "Running dhclient on $i"
                    interfaces="$interfaces $i"
                fi
            done

            if test -z "$interfaces"; then
                echo 'No interfaces on which to start dhclient!'
                exit 1
            fi

            mkdir -m 755 -p ${stateDir}

            exec ${dhcp}/sbin/dhclient -d $interfaces -e "PATH=$PATH" -lf ${stateDir}/dhclient.leases
        end script
      '';
    };

    environment.systemPackages = [dhcp];

    environment.etc =
      [ # Dhclient hooks for emitting ip-up/ip-down events.
        { source = dhclientExitHooks;
          target = "dhclient-exit-hooks";
        }
      ];

  };  
  
}

