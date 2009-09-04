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
        
          services.httpd.enable = true;
          services.httpd.adminAddr = "foo@example.org";
          services.httpd.documentRoot = "${pkgs.valgrind}/share/doc/valgrind/html";
  
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

          users.extraUsers = pkgs.lib.singleton
            { name = "alice";
              description = "Alice Foobar";
              home = "/home/alice";
              createHome = true;
              useDefaultShell = true;
              password = "foobar";
            };

          environment.systemPackages = [ pkgs.scrot ];
        };
    };

  vms = buildVirtualNetwork { inherit nodes; };

  test = runTests vms
    ''
      startAll;

      $client->waitForFile("/tmp/.X11-unix/X0");

      sleep 50;

      print STDERR $client->execute("su - alice -c 'DISPLAY=:0.0 kwrite /var/log/messages &'");

      sleep 10;
      
      print STDERR $client->execute("su - alice -c 'DISPLAY=:0.0 konqueror http://localhost/ &'");

      sleep 10;
      
      print STDERR $client->execute("DISPLAY=:0.0 scrot /hostfs/$ENV{out}/screen.png");
    '';
  
}
