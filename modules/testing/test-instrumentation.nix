# This module allows the test driver to connect to the virtual machine
# via a root shell attached to port 514.

{ config, pkgs, ... }:

with pkgs.lib;

let

  # Urgh, `socat' sets the SIGCHLD to ignore.  This wreaks havoc with
  # some programs.
  rootShell = pkgs.writeScript "shell.pl"
    ''
      #! ${pkgs.perl}/bin/perl
      $SIG{CHLD} = 'DEFAULT';
      exec "/bin/sh";
    '';

in
    
{

  config = {

    jobs.backdoor =
      { startOn = "started network-interfaces";
        
        preStart =
          ''
            echo "guest running" > /dev/ttyS0
            echo "===UP===" > dev/ttyS0
          '';
          
        script =
          ''
            export USER=root
            export HOME=/root
            export DISPLAY=:0.0
            export GCOV_PREFIX=/tmp/coverage-data
            source /etc/profile
            cd /tmp
            exec ${pkgs.socat}/bin/socat tcp-listen:514,fork exec:${rootShell} 2> /dev/ttyS0
          '';
      };
  
    boot.postBootCommands =
      ''
        # Panic on out-of-memory conditions rather than letting the
        # OOM killer randomly get rid of processes, since this leads
        # to failures that are hard to diagnose.
        echo 2 > /proc/sys/vm/panic_on_oom

        # Coverage data is written into /tmp/coverage-data.  Symlink
        # it to the host filesystem so that we don't need to copy it
        # on shutdown.
        ( eval $(cat /proc/cmdline)
          mkdir /hostfs/$hostTmpDir/coverage-data
          ln -s /hostfs/$hostTmpDir/coverage-data /tmp/coverage-data
        )

        # Mount debugfs to gain access to the kernel coverage data (if
        # available).
        mount -t debugfs none /sys/kernel/debug || true
      '';

    # If the kernel has been built with coverage instrumentation, make
    # it available under /proc/gcov.
    boot.kernelModules = [ "gcov-proc" ];

    # Panic if an error occurs in stage 1 (rather than waiting for
    # user intervention). 
    boot.kernelParams = [ "stage1panic" ];

    # `xwininfo' is used by the test driver to query open windows.
    environment.systemPackages = [ pkgs.xorg.xwininfo ];
      
  };

}
