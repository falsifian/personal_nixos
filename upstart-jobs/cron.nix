{pkgs, config, ...}:

###### interface
let
  inherit (pkgs.lib) mkOption;

  options = {
    services = {
      cron = {

        mailto = mkOption {
          default = "";
          description = " The job output will be mailed to this email address. ";
        };

        systemCronJobs = mkOption {
          default = [];
          example = [
            "* * * * *  test   ls -l / > /tmp/cronout 2>&1"
            "* * * * *  eelco  echo Hello World > /home/eelco/cronout"
          ];
          description = ''
            A list of Cron jobs to be appended to the system-wide
            crontab.  See the manual page for crontab for the expected
            format. If you want to get the results mailed you must setuid
            sendmail. See <option>security.setuidOwners</option>

            If neither /var/cron/cron.deny nor /var/cron/cron.allow exist only root
            will is allowed to have its own crontab file. The /var/cron/cron.deny file
            is created automatically for you. So every user can use a crontab.
          '';
        };

      };
    };
  };
in

###### implementation
let
  inherit (config.services) jobsTags;

  # Put all the system cronjobs together.
  systemCronJobs =
    config.services.cron.systemCronJobs;

  systemCronJobsFile = pkgs.writeText "system-crontab" ''
    SHELL=${pkgs.bash}/bin/sh
    PATH=${pkgs.coreutils}/bin:${pkgs.findutils}/bin:${pkgs.gnused}/bin:${pkgs.su}/bin
    MAILTO="${config.services.cron.mailto}"
    ${pkgs.lib.concatStrings (map (job: job + "\n") systemCronJobs)}
  '';
in

{
  require = [
    (import ../upstart-jobs/default.nix) # config.services.extraJobs
    # (import ?) # config.time.timeZone
    # (import ?) # config.environment.etc
    # (import ?) # config.environment.extraPackages
    # (import ?) # config.environment.cleanStart
    options
  ];

  environment = {
    etc = [
      # The system-wide crontab.
      { source = systemCronJobsFile;
        target = "crontab";
        mode = "0600"; # Cron requires this.
      }
    ];

    extraPackages =
      pkgs.lib.optional
        (!config.environment.cleanStart)
        pkgs.cron;
  };

  services = {
    extraJobs = [{
      name = "cron";

      job = ''
        description "Cron daemon"

        start on startup
        stop on shutdown

        # Needed to interpret times in the local timezone.
        env TZ=${config.time.timeZone}

        start script
            mkdir -m 710 -p /var/cron

            # By default, allow all users to create a crontab.  This
            # is denoted by the existence of an empty cron.deny file.
            if ! test -e /var/cron/cron.allow -o -e /var/cron/cron.deny; then
                touch /var/cron/cron.deny
            fi
        end script

        respawn ${pkgs.cron}/sbin/cron -n
      '';
    }];
  };
}
