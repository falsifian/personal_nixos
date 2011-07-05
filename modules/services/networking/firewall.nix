/* This module enables a simple firewall.

   The firewall can be customised in arbitrary ways by setting
   ‘networking.firewall.extraCommands’.  For modularity, the firewall
   uses several chains:

   - ‘nixos-fw-input’ is the main chain for input packet processing.
   
   - ‘nixos-fw-log-refuse’ and ‘nixos-fw-refuse’ are called for
     refused packets.  (The former jumps to the latter after logging
     the packet.)  If you want additional logging, or want to accept
     certain packets anyway, you can insert rules at the start of
     these chain.

   - ‘nixos-fw-accept’ is called for accepted packets.  If you want
     additional logging, or want to reject certain packets anyway, you
     can insert rules at the start of this chain.

*/
  


{ config, pkgs, ... }:

with pkgs.lib;

let

  cfg = config.networking.firewall;

  helpers =
    ''
      # Helper command to manipulate both the IPv4 and IPv6 tables.
      ip46tables() {
        iptables "$@"
        ip6tables "$@"
      }
    '';

in

{

  ###### interface

  options = {
  
    networking.firewall.enable = mkOption {
      default = false;
      description =
        ''
          Whether to enable the firewall.  This is a simple stateful
          firewall that blocks connection attempts to unauthorised TCP
          or UDP ports on this machine.  It does not affect packet
          forwarding.
        '';
    };
  
    networking.firewall.logRefusedConnections = mkOption {
      default = true;
      description =
        ''
          Whether to log rejected or dropped incoming connections.
        '';
    };
  
    networking.firewall.logRefusedPackets = mkOption {
      default = false;
      description =
        ''
          Whether to log all rejected or dropped incoming packets.
          This tends to give a lot of log messages, so it's mostly
          useful for debugging.
        '';
    };

    networking.firewall.logRefusedUnicastsOnly = mkOption {
      default = true;
      description =
        ''
          If <option>networking.firewall.logRefusedPackets</option>
          and this option are enabled, then only log packets
          specifically directed at this machine, i.e., not broadcasts
          or multicasts.
        '';
    };

    networking.firewall.rejectPackets = mkOption {
      default = false;
      description =
        ''
          If set, forbidden packets are rejected rather than dropped
          (ignored).  This means that a ICMP "port unreachable" error
          message is sent back to the client.  Rejecting packets makes
          port scanning somewhat easier.
        '';
    };
  
    networking.firewall.allowedTCPPorts = mkOption {
      default = [];
      example = [ 22 80 ];
      type = types.list types.int;
      description =
        ''
          List of TCP ports on which incoming connections are
          accepted.
        '';
    };
  
    networking.firewall.allowedUDPPorts = mkOption {
      default = [];
      example = [ 53 ];
      type = types.list types.int;
      description =
        ''
          List of open UDP ports.
        '';
    };
  
    networking.firewall.allowPing = mkOption {
      default = false;
      type = types.bool;
      description =
        ''
          Whether to respond to incoming ICMPv4 echo requests
          ("pings").  ICMPv6 pings are always allowed because the
          larger address space of IPv6 makes network scanning much
          less effective.
        '';
    };
  
    networking.firewall.extraCommands = mkOption {
      default = "";
      example = "iptables -A INPUT -p icmp -j ACCEPT";
      description =
        ''
          Additional shell commands executed as part of the firewall
          initialisation script.  These are executed just before the
          final "reject" firewall rule is added, so they can be used
          to allow packets that would otherwise be refused.
        '';
    };
  
  };


  ###### implementation

  # !!! Maybe if `enable' is false, the firewall should still be built
  # but not started by default.  However, currently nixos-rebuild
  # doesn't deal with such Upstart jobs properly (it starts them if
  # they are changed, regardless of whether the start condition
  # holds).
  config = mkIf cfg.enable {

    environment.systemPackages = [ pkgs.iptables ];

    boot.kernelModules = [ "nf_conntrack_ftp" ];

    jobs.firewall =
      { startOn = "started network-interfaces";

        path = [ pkgs.iptables ];

        preStart =
          ''
            ${helpers}
            set -x

            # Flush the old firewall rules.  !!! Ideally, updating the
            # firewall would be atomic.  Apparently that's possible
            # with iptables-restore.
            ip46tables -D INPUT -j nixos-fw || true
            for chain in nixos-fw nixos-fw-accept nixos-fw-log-refuse nixos-fw-refuse FW_REFUSE; do
              ip46tables -F "$chain" || true
              ip46tables -X "$chain" || true
            done


            # The "nixos-fw-accept" chain just accepts packets.
            ip46tables -N nixos-fw-accept
            ip46tables -A nixos-fw-accept -j ACCEPT


            # The "nixos-fw-refuse" chain rejects or drops packets.
            ip46tables -N nixos-fw-refuse
            
            ${if cfg.rejectPackets then ''
              # Send a reset for existing TCP connections that we've
              # somehow forgotten about.  Send ICMP "port unreachable"
              # for everything else.
              ip46tables -A nixos-fw-refuse -p tcp ! --syn -j REJECT --reject-with tcp-reset
              ip46tables -A nixos-fw-refuse -j REJECT
            '' else ''
              ip46tables -A nixos-fw-refuse -j DROP
            ''}


            # The "nixos-fw-log-refuse" chain performs logging, then
            # jumps to the "nixos-fw-refuse" chain.
            ip46tables -N nixos-fw-log-refuse

            ${optionalString cfg.logRefusedConnections ''
              ip46tables -A nixos-fw-log-refuse -p tcp --syn -j LOG --log-level info --log-prefix "rejected connection: "
            ''}
            ${optionalString (cfg.logRefusedPackets && !cfg.logRefusedUnicastsOnly) ''
              ip46tables -A nixos-fw-log-refuse -m pkttype --pkt-type broadcast \
                -j LOG --log-level info --log-prefix "rejected broadcast: "
              ip46tables -A nixos-fw-log-refuse -m pkttype --pkt-type multicast \
                -j LOG --log-level info --log-prefix "rejected multicast: "
            ''}
            ip46tables -A nixos-fw-log-refuse -m pkttype ! --pkt-type unicast -j nixos-fw-refuse
            ${optionalString cfg.logRefusedPackets ''
              ip46tables -A nixos-fw-log-refuse \
                -j LOG --log-level info --log-prefix "rejected packet: "
            ''}
            ip46tables -A nixos-fw-log-refuse -j nixos-fw-refuse


            # The "nixos-fw" chain does the actual work.
            ip46tables -N nixos-fw
            
            # Accept all traffic on the loopback interface.
            ip46tables -A nixos-fw -i lo -j nixos-fw-accept

            # Accept packets from established or related connections.
            ip46tables -A nixos-fw -m conntrack --ctstate ESTABLISHED,RELATED -j nixos-fw-accept

            # Accept connections to the allowed TCP ports.
            ${concatMapStrings (port:
                ''
                  ip46tables -A nixos-fw -p tcp --dport ${toString port} -j nixos-fw-accept
                ''
              ) cfg.allowedTCPPorts
            }

            # Accept packets on the allowed UDP ports.
            ${concatMapStrings (port:
                ''
                  ip46tables -A nixos-fw -p udp --dport ${toString port} -j nixos-fw-accept
                ''
              ) cfg.allowedUDPPorts
            }

            # Accept IPv4 multicast.  Not a big security risk since
            # probably nobody is listening anyway.
            #iptables -A nixos-fw -d 224.0.0.0/4 -j nixos-fw-accept

            # Optionally respond to ICMPv4 pings.
            ${optionalString cfg.allowPing ''
              iptables -A nixos-fw -p icmp --icmp-type echo-request -j nixos-fw-accept
            ''}

            # Accept all ICMPv6 messages except redirects and node
            # information queries (type 139).  See RFC 4890, section
            # 4.4.
            ip6tables -A nixos-fw -p icmpv6 --icmpv6-type redirect -j DROP
            ip6tables -A nixos-fw -p icmpv6 --icmpv6-type 139 -j DROP
            ip6tables -A nixos-fw -p icmpv6 -j nixos-fw-accept

            ${cfg.extraCommands}

            # Reject/drop everything else.
            ip46tables -A nixos-fw -j nixos-fw-log-refuse


            # Enable the firewall.
            ip46tables -A INPUT -j nixos-fw
          '';

        postStop =
          ''
            ${helpers}
            ip46tables -D INPUT -j nixos-fw || true
            #ip46tables -P INPUT ACCEPT
          '';
      };

  };

}
