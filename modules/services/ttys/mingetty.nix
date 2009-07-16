{pkgs, config, ...}:

let

  inherit (pkgs.lib) mkOption mkIf singleton;
  
in

{

  ###### interface

  options = {
  
    services.mingetty = {

      ttys = mkOption {
        default = [1 2 3 4 5 6];
        description = ''
          The list of tty (virtual console) devices on which to start a
          login prompt.
        '';
      };

      waitOnMounts = mkOption {
        default = false;
        description = ''
          Whether the login prompts on the virtual consoles will be
          started before or after all file systems have been mounted.  By
          default we don't wait, but if for example your /home is on a
          separate partition, you may want to turn this on.
        '';
      };

      greetingLine = mkOption {
        default = ''<<< Welcome to NixOS (\m) - Kernel \r (\l) >>>'';
        description = ''
          Welcome line printed by mingetty.
        '';
      };

      helpLine = mkOption {
        default = "";
        description = ''
          Help line printed by mingetty below the welcome line.
          Used by the installation CD to give some hints on
          how to proceed.
        '';
      };

    };
    
  };


  ###### implementation

  config = {

    # Generate a separate job for each tty.  
    jobs = map (ttyNumber: {
    
      name = "tty${toString ttyNumber}";

      startOn = "udev";

      exec = "${pkgs.mingetty}/sbin/mingetty --loginprog=${pkgs.pam_login}/bin/login --noclear tty${toString ttyNumber}";
      
    }) config.services.mingetty.ttys;

    environment.etc = singleton
      { # Friendly greeting on the virtual consoles.
        source = pkgs.writeText "issue" ''
      
          [1;32m${config.services.mingetty.greetingLine}[0m
          ${config.services.mingetty.helpLine}
        
        '';
        target = "issue";
      };
  };
  
}
