{ config, pkgs, ... }:

with pkgs.lib;

let

  inherit (pkgs) nettools;

  cfg = config.networking;

  ifconfig = "${nettools}/sbin/ifconfig";

in 

{

  ###### interface

  options = {

    networking.hostName = mkOption {
      default = "nixos";
      description = ''
        The name of the machine.  Leave it empty if you want to obtain
        it from a DHCP server (if using DHCP).
      '';
    };

    networking.enableIPv6 = mkOption {
      default = true;
      description = ''
        Whether to enable support for IPv6.
      '';
    };

    networking.defaultGateway = mkOption {
      default = "";
      example = "131.211.84.1";
      description = ''
        The default gateway.  It can be left empty if it is auto-detected through DHCP.
      '';
    };

    networking.nameservers = mkOption {
      default = [];
      example = ["130.161.158.4" "130.161.33.17"];
      description = ''
        The list of nameservers.  It can be left empty if it is auto-detected through DHCP.
      '';
    };

    networking.domain = mkOption {
      default = "";
      example = "home";
      description = ''
        The domain.  It can be left empty if it is auto-detected through DHCP.
      '';
    };

    networking.localCommands = mkOption {
      default = "";
      example = "text=anything; echo You can put $text here.";
      description = ''
        Shell commands to be executed at the end of the
        <literal>network-interfaces</literal> Upstart job.  Note that if
        you are using DHCP to obtain the network configuration,
        interfaces may not be fully configured yet.
      '';
    };

    networking.interfaces = mkOption {
      default = [];
      example = [
        { name = "eth0";
          ipAddress = "131.211.84.78";
          subnetMask = "255.255.255.128";
        }
      ];
      description = ''
        The configuration for each network interface.  If
        <option>networking.useDHCP</option> is true, then every
        interface not listed here will be configured using DHCP.
      '';

      type = types.list types.optionSet;

      options = {

        name = mkOption {
          example = "eth0";
          type = types.string;
          description = ''
            Name of the interface.
          '';
        };

        ipAddress = mkOption {
          default = "";
          example = "10.0.0.1";
          type = types.string;
          description = ''
            IP address of the interface.  Leave empty to configure the
            interface using DHCP.
          '';
        };

        subnetMask = mkOption {
          default = "";
          example = "255.255.255.0";
          type = types.string;
          description = ''
            Subnet mask of the interface.  Leave empty to use the
            default subnet mask.
          '';
        };

        macAddress = mkOption {
          default = "";
          example = "00:11:22:33:44:55";
          type = types.string;
          description = ''
            MAC address of the interface. Leave empty to use the default.
          '';
        };

      };
      
    };

    networking.ifaces = mkOption {
      default = listToAttrs
        (map (iface: { name = iface.name; value = iface; }) config.networking.interfaces);
      internal = true;
      description = ''
        The network interfaces in <option>networking.interfaces</option>
        as an attribute set keyed on the interface name.
      '';
    };
    
  };


  ###### implementation

  config = {

    boot.kernelModules = optional cfg.enableIPv6 "ipv6";

    environment.systemPackages =
      [ pkgs.host
        pkgs.iproute
        pkgs.iputils
        pkgs.nettools
        pkgs.wirelesstools
        pkgs.rfkill
      ];

    security.setuidPrograms = [ "ping" "ping6" ];
    
    jobs.networkInterfaces = 
      { name = "network-interfaces";

        startOn = "stopped udevtrigger";

        path = [ config.system.sbin.modprobe pkgs.iproute ];

        preStart =
          ''
            modprobe af_packet || true

            ${pkgs.lib.concatMapStrings (i:
              if i.macAddress != "" then
                ''
                  echo "Configuring interface ${i.name}..."
                  ${ifconfig} "${i.name}" down || true
                  ${ifconfig} "${i.name}" hw ether "${i.macAddress}" || true
                ''
              else "") cfg.interfaces
            }

            for i in $(cd /sys/class/net && ls -d *); do
                echo "Bringing up network device $i..."
                ${ifconfig} $i up || true
            done

            # Configure the manually specified interfaces.
            ${pkgs.lib.concatMapStrings (i:
              if i.ipAddress != "" then
                ''
                  echo "Configuring interface ${i.name}..."
                  extraFlags=
                  if test -n "${i.subnetMask}"; then
                      extraFlags="$extraFlags netmask ${i.subnetMask}"
                  fi
                  ${ifconfig} "${i.name}" "${i.ipAddress}" $extraFlags || true
                ''
              else "") cfg.interfaces}

            # Set the nameservers.
            if test -n "${toString cfg.nameservers}"; then
                rm -f /etc/resolv.conf
                if test -n "${cfg.domain}"; then
                    echo "domain ${cfg.domain}" >> /etc/resolv.conf
                fi
                for i in ${toString cfg.nameservers}; do
                    echo "nameserver $i" >> /etc/resolv.conf
                done
            fi

            # Set the default gateway.
            if test -n "${cfg.defaultGateway}"; then
                ${nettools}/sbin/route add default gw "${cfg.defaultGateway}" || true
            fi

            # Run any user-specified commands.
            ${pkgs.stdenv.shell} ${pkgs.writeText "local-net-cmds" cfg.localCommands} || true

            ${optionalString (cfg.interfaces != [] || cfg.localCommands != "") ''
              # Emit the ip-up event (e.g. to start ntpd).
              initctl emit -n ip-up
            ''}
          '';

        postStop =
          ''
            #for i in $(cd /sys/class/net && ls -d *); do
            #    echo "Taking down network device $i..."
            #    ${ifconfig} $i down || true
            #done
          '';
      };

    # Set the host name in the activation script.  Don't clear it if
    # it's not configured in the NixOS configuration, since it may
    # have been set by dhclient in the meantime.
    system.activationScripts.hostname =
      optionalString (config.networking.hostName != "") ''
        hostname "${config.networking.hostName}"
      '';

  };
  
}
