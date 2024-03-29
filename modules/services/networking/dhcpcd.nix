{ config, pkgs, ... }:

with pkgs.lib;

let

  inherit (pkgs) dhcpcd;

  # Don't start dhclient on explicitly configured interfaces or on
  # interfaces that are part of a bridge.
  ignoredInterfaces =
    map (i: i.name) (filter (i: i ? ipAddress && i.ipAddress != "" ) config.networking.interfaces)
    ++ concatLists (attrValues (mapAttrs (n: v: v.interfaces) config.networking.bridges));

  # Config file adapted from the one that ships with dhcpcd.
  dhcpcdConf = pkgs.writeText "dhcpcd.conf"
    ''
      # Inform the DHCP server of our hostname for DDNS.
      hostname

      # A list of options to request from the DHCP server.
      option domain_name_servers, domain_name, domain_search, host_name
      option classless_static_routes, ntp_servers, interface_mtu

      # A ServerID is required by RFC2131.
      require dhcp_server_identifier

      # A hook script is provided to lookup the hostname if not set by
      # the DHCP server, but it should not be run by default.
      nohook lookup-hostname

      # Ignore peth* devices; on Xen, they're renamed physical
      # Ethernet cards used for bridging.  Likewise for vif* and tap*
      # (Xen) and virbr* and vnet* (libvirt).
      denyinterfaces ${toString ignoredInterfaces} peth* vif* tap* tun* virbr* vnet* vboxnet*
    '';

  # Hook for emitting ip-up/ip-down events.
  exitHook = pkgs.writeText "dhcpcd.exit-hook"
    ''
      #exec >> /var/log/dhcpcd 2>&1
      #set -x

      params="IFACE=$interface REASON=$reason"

      # only works when interface is wireless and wpa_supplicant has a control socket
      # but we allow it to fail silently
      ${optionalString config.networking.wireless.enable ''
        params+=" $(${pkgs.wpa_supplicant}/sbin/wpa_cli -i$interface status 2>/dev/null | grep ssid | sed 's|^b|B|;s|ssid|SSID|' | xargs)"
      ''}

      if [ "$reason" = BOUND -o "$reason" = REBOOT ]; then
          # Restart ntpd.  (The "ip-up" event below will trigger the
          # restart.)  We need to restart it to make sure that it will
          # actually do something: if ntpd cannot resolve the server
          # hostnames in its config file, then it will never do
          # anything ever again ("couldn't resolve ..., giving up on
          # it"), so we silently lose time synchronisation.
          ${config.system.build.upstart}/sbin/initctl stop ntpd

          ${config.system.build.upstart}/sbin/initctl emit -n ip-up $params
      fi

      if [ "$reason" = EXPIRE -o "$reason" = RELEASE -o "$reason" = NOCARRIER ] ; then
          ${config.system.build.upstart}/sbin/initctl emit -n ip-down $params
      fi
    '';

in

{

  ###### implementation

  config = mkIf config.networking.useDHCP {

    jobs.dhcpcd =
      { startOn = "started network-interfaces";

        path = [ dhcpcd pkgs.nettools pkgs.openresolv ];

        exec = "dhcpcd --config ${dhcpcdConf} --nobackground";
      };

    environment.systemPackages = [ dhcpcd ];

    environment.etc =
      [ { source = exitHook;
          target = "dhcpcd.exit-hook";
        }
      ];

    powerManagement.resumeCommands =
      ''
        # Tell dhcpcd to rebind its interfaces if it's running.
        status="$(${config.system.build.upstart}/sbin/status dhcpcd)"
        [[ "$status" =~ start/running ]] && ${dhcpcd}/sbin/dhcpcd --rebind
      '';

  };

}
