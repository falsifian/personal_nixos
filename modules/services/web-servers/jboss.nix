{pkgs, config, ...}:

###### interface
let
  inherit (pkgs.lib) mkOption mkIf;

  options = {
    services = {
      jboss = {
        enable = mkOption {
          default = false;
          description = "Whether to enable jboss";
        };

        tempDir = mkOption {
          default = "/tmp";
          description = "Location where JBoss stores its temp files";
        };
        
        logDir = mkOption {
          default = "/var/log/jboss";
          description = "Location of the logfile directory of JBoss";
        };
        
        serverDir = mkOption {
          description = "Location of the server instance files";
          default = "/var/jboss/server";
        };
        
        deployDir = mkOption {
          description = "Location of the deployment files";
          default = "/nix/var/nix/profiles/default/server/default/deploy/";
        };
        
        libUrl = mkOption {
          default = "file:///nix/var/nix/profiles/default/server/default/lib";
          description = "Location where the shared library JARs are stored";
        };
        
        user = mkOption {
          default = "nobody";
          description = "User account under which jboss runs.";
        };
        
        useJK = mkOption {
          default = false;
          description = "Whether to use to connector to the Apache HTTP server";
        };
      };
    };
  };
in

###### implementation
let

cfg = config.services.jboss;
jbossService = import ../../services/jboss {
        inherit (pkgs) stdenv jboss su;
        inherit (cfg) tempDir logDir libUrl deployDir serverDir user useJK;
};

in

mkIf config.services.jboss.enable {
  require = [
    options
  ];

  services = {
    extraJobs = [{
      name = "jboss";
      job = ''
          description \"JBoss server\"

          stop on shutdown

          respawn ${jbossService}/bin/control start
      '';
    }];
  };
}
