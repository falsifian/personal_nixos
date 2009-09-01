{ nixos ? ./..
, nixpkgs ? /etc/nixos/nixpkgs
, services ? /etc/nixos/services
}:

with import ../lib/build-vms.nix { inherit nixos nixpkgs services; };

let

  # Build some packages with coverage instrumentation.
  overrides = pkgs:  
    let
      do = pkg: pkg.override (args: {
        stdenv = pkgs.addCoverageInstrumentation args.stdenv;
      });
    in
      rec {
        apr = do pkgs.apr;
        aprutil = do pkgs.aprutil;
        apacheHttpd = do pkgs.apacheHttpd;
        mod_python = do pkgs.mod_python;
        subversion = do pkgs.subversion;

        # To build the kernel with coverage instrumentation, we need a
        # special patch to make coverage data available under /proc.
        kernel_2_6_28 = pkgs.kernel_2_6_28.override (orig: {
          stdenv = pkgs.keepBuildTree orig.stdenv;
          kernelPatches = orig.kernelPatches ++ pkgs.lib.singleton
            { name = "gcov";
              patch = pkgs.fetchurl {
                url = http://buildfarm.st.ewi.tudelft.nl/~eelco/dist/linux-2.6.28-gcov.patch;
                sha256 = "0ck9misa3pgh3vzyb7714ibf7ix7piyg5dvfa9r42v15scjqiyny";
              };
              extraConfig =
                ''
                  CONFIG_GCOV_PROFILE=y
                  CONFIG_GCOV_ALL=y
                  CONFIG_GCOV_PROC=m
                  CONFIG_GCOV_HAMMER=n
                '';
            };
        });
      };

in
      
rec {

  nodes =
    { webserver =
        { config, pkgs, ... }:

        {
          boot.kernelModules = [ "gcov-proc" ];
          services.httpd.enable = true;
          services.httpd.adminAddr = "e.dolstra@tudelft.nl";
          services.httpd.extraSubservices =
            [ { serviceType = "subversion";
                urlPrefix = "";
                dataDir = "/data/subversion";
                userCreationDomain = "192.168.0.0/16";
              }
            ];
          nixpkgs.config.packageOverrides = overrides;
        };

      client =
        { config, pkgs, ... }:

        {
          environment.systemPackages = [ pkgs.subversion ];
          nixpkgs.config.packageOverrides = overrides;
        };

    };

  vms = buildVirtualNetwork { inherit nodes; };

  test = runTests vms
    ''
      startAll;

      $webserver->waitForOpenPort(80);

      my $out = $client->mustSucceed("svn --version");
      print STDERR "GOT: $out";

      my $out = $client->mustSucceed("curl --fail http://webserver/");
      print STDERR "GOT: $out";

      # Create a new user through the web interface.
      $client->mustSucceed("curl --fail -F username=alice -F fullname='Alice Lastname' -F address=alice\@example.org -F password=foobar -F password_again=foobar http://webserver/repoman/adduser");

      # Let Alice create a new repository.      
      $client->mustSucceed("curl --fail -u alice:foobar --form repo=xyzzy --form description=Xyzzy http://webserver/repoman/create");

      $client->mustSucceed("curl --fail http://webserver/") =~ /alice/ or die;
      
      # Let Alice do a checkout.
      my $svnFlags = "--non-interactive --username alice --password foobar";
      $client->mustSucceed("svn co $svnFlags http://webserver/repos/xyzzy wc");
      $client->mustSucceed("echo hello > wc/world");
      $client->mustSucceed("svn add wc/world");
      $client->mustSucceed("svn ci $svnFlags -m 'Added world.' wc/world");

      # Create a new user on the server through the create-user.pl script.
      $webserver->execute("svn-server-create-user.pl bob bob\@example.org Bob");
      $webserver->mustSucceed("svn-server-resetpw.pl bob fnord");
      $client->mustSucceed("curl --fail http://webserver/") =~ /bob/ or die;

      # Bob should not have access to the repo.
      my $svnFlagsBob = "--non-interactive --username bob --password fnord";
      $client->mustFail("svn co $svnFlagsBob http://webserver/repos/xyzzy wc2");

      # Bob should not be able change the ACLs of the repo.
      # !!! Repoman should really return a 403 here.
      $client->execute("curl --fail -u bob:fnord -F description=Xyzzy -F readers=alice,bob -F writers=alice -F watchers= -F tardirs= http://webserver/repoman/update/xyzzy")
          =~ /not authorised/ or die;
      
      # Give Bob access.
      $client->mustSucceed("curl --fail -u alice:foobar -F description=Xyzzy -F readers=alice,bob -F writers=alice -F watchers= -F tardirs= http://webserver/repoman/update/xyzzy");
      
      # So now his checkout should succeed.
      $client->mustSucceed("svn co $svnFlagsBob http://webserver/repos/xyzzy wc2");

      # Test ViewVC and WebSVN
      $client->mustSucceed("curl --fail -u alice:foobar http://webserver/viewvc/xyzzy");
      $client->mustSucceed("curl --fail -u alice:foobar http://webserver/websvn/xyzzy");
      $client->mustSucceed("curl --fail -u alice:foobar http://webserver/repos-xml/xyzzy");

      # Stop Apache to gather all the coverage data.
      $webserver->stopJob("httpd");
      $webserver->execute("sleep 10"); # !!!

      # !!! move this to build-vms.nix
      my $kernelDir = $webserver->mustSucceed("echo \$(dirname \$(readlink -f /var/run/current-system/kernel))/.build/linux-*");
      chomp $kernelDir;
      my $coverageDir = "/hostfs" . $webserver->stateDir() . "/coverage-data/$kernelDir";
      $webserver->execute("for i in \$(cd /proc/gcov && find -name module -prune -o -name '*.gcda'); do echo \$i; mkdir -p $coverageDir/\$(dirname \$i); cp -v /proc/gcov/\$i $coverageDir/\$i; done");
      $webserver->execute("for i in \$(cd /proc/gcov/module/nix/store/*/.build/* && find -name module -prune -o -name '*.gcda'); do mkdir -p $coverageDir/\$(dirname \$i); cp /proc/gcov/module/nix/store/*/.build/*/\$i $coverageDir/\$i; done");
    '';

  report = makeReport test;
    
}
