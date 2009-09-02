{ nixos ? ./..
, nixpkgs ? /etc/nixos/nixpkgs
, services ? /etc/nixos/services
, system ? builtins.currentSystem
}:

with import ../lib/build-vms.nix { inherit nixos nixpkgs services system; };

rec {

  nodes =
    { client =
        { config, pkgs, ... }:

        { services.xserver.enable = true;
        
          services.xserver.displayManager.slim.enable = false;
          services.xserver.displayManager.kdm.enable = true;
          services.xserver.displayManager.kdm.extraConfig =
            ''
              [X-:0-Core]
              AutoLoginEnable=true
              AutoLoginUser=alice
              AutoLoginPass=foobar
            '';
            
          services.xserver.desktopManager.default = "kde4";
          services.xserver.desktopManager.kde4.enable = true;

          services.sshd.enable = true;

          users.extraUsers = pkgs.lib.singleton
            { name = "alice";
              description = "Alice Foobar";
              home = "/home/alice";
              createHome = true;
              useDefaultShell = true;
              password = "foobar";
            };

          environment.systemPackages = [ pkgs.xorg.xclock pkgs.xorg.xwd ];
        };
    };

  vms = buildVirtualNetwork { inherit nodes; };

  test = runTests vms
    ''
      startAll;

      $client->waitForFile("/tmp/.X11-unix/X0");

      sleep 60;

      print STDERR $client->execute("DISPLAY=:0.0 xwd -root > /hostfs/$ENV{out}/screen.xwd");
    '';
  
}
