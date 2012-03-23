# Module for VirtualBox guests.

{ config, pkgs, ... }:

with pkgs.lib;

let

  cfg = config.services.virtualbox;
  kernel = config.boot.kernelPackages;

in

{

  ###### interface

  options = {

    services.virtualbox = {

      enable = mkOption {
        default = false;
        description = "Whether to enable the VirtualBox service and other guest additions.";
      };

    };

  };


  ###### implementation

  config = mkIf cfg.enable {

    environment.systemPackages = [ kernel.virtualboxGuestAdditions ];

    boot.extraModulePackages = [ kernel.virtualboxGuestAdditions ];

    jobs.virtualbox =
      { description = "VirtualBox service";

        startOn = "started udev";

        exec = "${kernel.virtualboxGuestAdditions}/sbin/VBoxService --foreground";
      };

    services.xserver.videoDrivers = mkOverride 50 [ "virtualbox" ];

    services.xserver.config =
      ''
        Section "InputDevice"
          Identifier "VBoxMouse"
          Driver "vboxmouse"
        EndSection
      '';

    services.xserver.serverLayoutSection =
      ''
        InputDevice "VBoxMouse"
      '';
    
    services.xserver.displayManager.sessionCommands =
      ''
        PATH=${makeSearchPath "bin" [ pkgs.gnugrep pkgs.which pkgs.xorg.xorgserver ]}:$PATH \
          ${kernel.virtualboxGuestAdditions}/bin/VBoxClient-all
      '';

    services.udev.extraRules =
      ''
        # /dev/vboxuser is necessary for VBoxClient to work.  Maybe we
        # should restrict this to logged-in users.
        KERNEL=="vboxuser",  OWNER="root", GROUP="root", MODE="0666"
      '';
      
  };

}
