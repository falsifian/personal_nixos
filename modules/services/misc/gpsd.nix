{pkgs, config, ...}:

###### interface
let
  inherit (pkgs.lib) mkOption mkIf;

  uid = config.ids.uids.gpsd;
  gid = config.ids.gids.gpsd;

  options = {
    services = {
      gpsd = {

        enable = mkOption {
          default = false;
          description = ''
            Whether to enable `gpsd', a GPS service daemon.
          '';
        };

        device = mkOption {
          default = "/dev/ttyUSB0";
          description = ''
            A device may be a local serial device for GPS input, or a URL of the form:
                 <literal>[{dgpsip|ntrip}://][user:passwd@]host[:port][/stream]</literal>
            in which case it specifies an input source for DGPS or ntrip data.
          '';
        };

        readonly = mkOption {
          default = true;
          description = ''
            Whether to enable the broken-device-safety, otherwise
            known as read-only mode.  Some popular bluetooth and USB
            receivers lock up or become totally inaccessible when
            probed or reconfigured.  This switch prevents gpsd from
            writing to a receiver.  This means that gpsd cannot
            configure the receiver for optimal performance, but it
            also means that gpsd cannot break the receiver.  A better
            solution would be for Bluetooth to not be so fragile.  A
            platform independent method to identify
            serial-over-Bluetooth devices would also be nice.
          '';
        };

        port = mkOption {
          default = 2947;
          description = ''
            The port where to listen for TCP connections.
          '';
        };

        debugLevel = mkOption {
          default = 0;
          description = ''
            The debugging level.
          '';
        };

      };
    };
  };

in

###### implementation
mkIf config.services.gpsd.enable {
  require = [
    options
  ];
  
  users = {
    extraUsers = [
      { name = "gpsd";
        inherit uid;
        description = "gpsd daemon user";
        home = "/var/empty";
      }
    ];

    extraGroups = [
      { name = "gpsd";
        inherit gid;
      }
    ];
  };

  services =
    let cfg = config.services.gpsd; in {
      extraJobs = [{
        name = "gpsd";

        job =
          let gpsd = pkgs.gpsd;
          in ''
            description "GPSD daemon"

            start on network-interfaces/started
            stop on network-interfaces/stop

            respawn ${gpsd}/sbin/gpsd -D "${toString cfg.debugLevel}"   \
                       -S "${toString cfg.port}"                        \
                       ${if cfg.readonly then "-b" else ""}             \
                       "${cfg.device}"
          '';
        }];
      };
}
