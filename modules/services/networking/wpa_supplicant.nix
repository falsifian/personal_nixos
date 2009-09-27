{pkgs, config, ...}:

let

  configFile = "/etc/wpa_supplicant.conf";

in

{

  ###### interface

  options = {
  
    networking.enableWLAN = pkgs.lib.mkOption {
      default = false;
      description = ''
        Whether to start <command>wpa_supplicant</command> to scan for
        and associate with wireless networks.  Note: NixOS currently
        does not generate <command>wpa_supplicant</command>'s
        configuration file, <filename>${configFile}</filename>.  You
        should edit this file yourself to define wireless networks,
        WPA keys and so on (see
        <citerefentry><refentrytitle>wpa_supplicant.conf</refentrytitle>
        <manvolnum>5</manvolnum></citerefentry>).
      '';
    };

  };


  ###### implementation
  
  config = pkgs.lib.mkIf config.networking.enableWLAN {

    environment.systemPackages = [pkgs.wpa_supplicant];

    jobs = pkgs.lib.singleton
      { name = "wpa_supplicant";

        startOn = "network-interfaces/started";
        stopOn = "network-interfaces/stop";

        preStart =
          ''
            touch -a ${configFile}
            chmod 600 ${configFile}
          '';

        exec =
          "${pkgs.wpa_supplicant}/sbin/wpa_supplicant " +
          "-C /var/run/wpa_supplicant -c ${configFile} -iwlan0";
      };
  
  };

}
