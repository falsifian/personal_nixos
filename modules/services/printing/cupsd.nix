{ config, pkgs, ... }:

with pkgs.lib;

let

  inherit (pkgs) cups;

  logDir = "/var/log/cups";

  modprobe = config.system.sbin.modprobe;

  cfg = config.services.printing;

  additionalBackends = pkgs.stdenv.mkDerivation {
    name = "additional-cups-backends";
    builder = pkgs.writeScript "additional-backends-builder.sh" ''
      PATH=${pkgs.coreutils}/bin
      mkdir -pv $out
      if [ ! -e ${pkgs.samba}/lib/cups/backend/smb ]; then
        mkdir -pv $out/lib/cups/backend
        ln -sv ${pkgs.samba}/bin/smbspool $out/lib/cups/backend/smb
      fi

      # Provide support for printing via HTTPS.
      if [ ! -e ${pkgs.cups}/lib/cups/backend/https ]; then
        mkdir -pv $out/lib/cups/backend
        ln -sv ${pkgs.cups}/lib/cups/backend/ipp $out/lib/cups/backend/https
      fi

      # Awful hack to get programs needed by some PPDs in CUPS'
      # hard-coded $PATH.
      mkdir -p $out/lib/cups/filter
      ln -s ${pkgs.coreutils}/bin/date ${pkgs.coreutils}/bin/cat ${pkgs.gnused}/bin/sed $out/lib/cups/filter/
    '';
  };

  # Here we can enable additional backends, filters, etc. that are not
  # part of CUPS itself, e.g. the SMB backend is part of Samba.  Since
  # we can't update ${cups}/lib/cups itself, we create a symlink tree
  # here and add the additional programs.  The ServerBin directive in
  # cupsd.conf tells cupsd to use this tree.
  bindir = pkgs.buildEnv {
    name = "cups-progs";
    paths = cfg.drivers;
    pathsToLink = [ "/lib/cups" "/share/cups" ];
    postBuild = cfg.bindirCmds;
  };

in

{

  ###### interface

  options = {
    services.printing = {

      enable = mkOption {
        default = false;
        description = ''
          Whether to enable printing support through the CUPS daemon.
        '';
      };

      bindirCmds = mkOption {
        default = "";
        description = ''
          Additional commands executed while creating the directory
          containing the CUPS server binaries.
        '';
      };

      cupsdConf = mkOption {
        default = "";
        example =
          ''
            BrowsePoll cups.example.com
            LogLevel debug
          '';
        description = ''
          The contents of the configuration file of the CUPS daemon
          (<filename>cupsd.conf</filename>).
        '';
      };

      drivers = mkOption {
        example = [ pkgs.splix ];
        description = ''
          CUPS drivers (CUPS, gs and samba are added unconditionally).
        '';
      };

      tempDir = mkOption {
        default = "/tmp";
        example = "/tmp/cups";
        description = ''
          CUPSd temporary directory.
        '';
      };
    };

  };


  ###### implementation

  config = mkIf config.services.printing.enable {

    users.extraUsers = singleton
      { name = "cups";
        uid = config.ids.uids.cups;
        group = "lp";
        description = "CUPS printing services";
      };

    environment.systemPackages = [ cups ];

    services.dbus.packages = [ cups ];

    # Cups uses libusb to talk to printers, and does not use the
    # linux kernel driver. If the driver is not in a black list, it
    # gets loaded, and then cups cannot access the printers.
    boot.blacklistedKernelModules = [ "usblp" ];

    jobs.cupsd =
      { description = "CUPS printing daemon";

        startOn = "started network-interfaces";
        stopOn = "stopping network-interfaces";

        path = [ config.system.path ];

        preStart =
          ''
            mkdir -m 0755 -p ${logDir}
            mkdir -m 0700 -p /var/cache/cups
            mkdir -m 0700 -p /var/spool/cups
            mkdir -m 0755 -p ${cfg.tempDir}
          '';

        exec = "${cups}/sbin/cupsd -c ${pkgs.writeText "cupsd.conf" cfg.cupsdConf} -F";
      };

    services.printing.drivers = [ pkgs.cups pkgs.cups_pdf_filter pkgs.ghostscript additionalBackends ];
    
    services.printing.cupsdConf =
      ''
        LogLevel info

        SystemGroup root

        Listen localhost:631
        Listen /var/run/cups/cups.sock

        # Note: we can't use ${cups}/etc/cups as the ServerRoot, since
        # CUPS will write in the ServerRoot when e.g. adding new printers
        # through the web interface.
        ServerRoot /etc/cups

        ServerBin ${bindir}/lib/cups
        DataDir ${bindir}/share/cups

        AccessLog ${logDir}/access_log
        ErrorLog ${logDir}/error_log
        PageLog ${logDir}/page_log

        TempDir ${cfg.tempDir}

        # User and group used to run external programs, including
        # those that actually send the job to the printer.  Note that
        # Udev sets the group of printer devices to `lp', so we want
        # these programs to run as `lp' as well.
        User cups
        Group lp

        Browsing On
        BrowseOrder allow,deny
        BrowseAllow @LOCAL

        DefaultAuthType Basic

        <Location />
          Order allow,deny
          Allow localhost
        </Location>

        <Location /admin>
          Order allow,deny
          Allow localhost
        </Location>

        <Location /admin/conf>
          AuthType Basic
          Require user @SYSTEM
          Order allow,deny
          Allow localhost
        </Location>

        <Policy default>
          <Limit Send-Document Send-URI Hold-Job Release-Job Restart-Job Purge-Jobs Set-Job-Attributes Create-Job-Subscription Renew-Subscription Cancel-Subscription Get-Notifications Reprocess-Job Cancel-Current-Job Suspend-Current-Job Resume-Job CUPS-Move-Job>
            Require user @OWNER @SYSTEM
            Order deny,allow
          </Limit>

          <Limit Pause-Printer Resume-Printer Set-Printer-Attributes Enable-Printer Disable-Printer Pause-Printer-After-Current-Job Hold-New-Jobs Release-Held-New-Jobs Deactivate-Printer Activate-Printer Restart-Printer Shutdown-Printer Startup-Printer Promote-Job Schedule-Job-After CUPS-Add-Printer CUPS-Delete-Printer CUPS-Add-Class CUPS-Delete-Class CUPS-Accept-Jobs CUPS-Reject-Jobs CUPS-Set-Default>
            AuthType Basic
            Require user @SYSTEM
            Order deny,allow
          </Limit>

          <Limit Cancel-Job CUPS-Authenticate-Job>
            Require user @OWNER @SYSTEM
            Order deny,allow
          </Limit>

          <Limit All>
            Order deny,allow
          </Limit>
        </Policy>
      '';

    # Allow CUPS to receive IPP printer announcements via UDP.
    networking.firewall.allowedUDPPorts = [ 631 ];

  };
}
