/*
platform ? __currentSystem
lib
*/
args: with args;

let
	arg = name: def: lib.getAttr [name] def args;
	platform = arg "platform" __currentSystem;
	networkNixpkgs = arg "networkNixpkgs" "";
	nixpkgsMd5 = arg "nixpkgsMd5" "";
	manualEnabled = arg "manualEnabled" true;
	rogueEnabled = arg "rogueEnabled" true;
	ttyCount = lib.fold builtins.add 0 [
	  (if rogueEnabled then 1 else 0)
	  (if manualEnabled then 1 else 0)
	];
	sshdEnabled = arg "sshdEnabled" false;
	fontConfigEnabled = arg "fontConfigEnabled" false;
	sudoEnable = arg "sudoEnable" false;
	packages = arg "packages" (pkgs : []);
	includeMemtest = arg "includeMemtest" true;
	includeStdenv = arg "includeStdenv" true;
	includeBuildDeps = arg "includeBuildDeps" false;
	kernel = arg "kernel" (pkgs : pkgs.kernel);
	addUsers = arg "addUsers" [];
	extraInitrdKernelModules = arg "extraInitrdKernelModules" [];
	bootKernelModules = arg "bootKernelModules" [];
	arbitraryOverrides = arg "arbitraryOverrides" (config:{});
	cleanStart = arg "cleanStart" false;

	/* Should return list of {configuration, suffix} attrsets.
	{configuration=configuration; suffix=""} is always prepended.
	*/
	configList = arg "configList" (configuration : []); 
in 
let

	systemPackBuilder = {suffix, configuration} : { 
		system = (import ../system/system.nix) {
			inherit configuration platform; /* To refactor later - x86+x86_64 DVD */
			stage2Init = "/init"+suffix;
		};
		inherit suffix configuration;
	};

	systemPackGrubEntry = systemPack : (''

          title NixOS Installer / Rescue ${systemPack.system.config.boot.configurationName}
            kernel /boot/vmlinuz${systemPack.suffix} ${toString systemPack.system.config.boot.kernelParams} systemConfig=/system${systemPack.suffix}
            initrd /boot/initrd${systemPack.suffix}

	'');

	systemPackInstallRootList = systemPack : [
	      { source = systemPack.system.kernel + "/vmlinuz";
		target = "boot/vmlinuz${systemPack.suffix}";
	      }
	      { source = systemPack.system.initialRamdisk + "/initrd";
		target = "boot/initrd${systemPack.suffix}";
	      }
	];
	systemPackInstallClosures = systemPack : ([
	      { object = systemPack.system.bootStage2;
		symlink = "/init${systemPack.suffix}";
	      }
	      { object = systemPack.system.system;
		symlink = "/system${systemPack.suffix}";
	      }
	]
	++
	    (lib.optional includeStdenv 
	      # To speed up the installation, provide the full stdenv.
	      { object = systemPack.system.pkgs.stdenv;
		symlink = "none";
	      }
	    )
	);
	systemPackInstallBuildClosure = systemPack : ([
		{
			object = systemPack.system.system.drvPath;
			symlink = "none";
		}
	]);


	userEntry = user : {
		name = user;
		description = "NixOS Live Disk non-root user";
		home = "/home/${user}";
		createHome = true;
		group = "users";
		extraGroups = ["wheel" "audio"];
		shell = "/bin/sh";
	};
in

rec {

  
  nixpkgsRel = "nixpkgs" + (if networkNixpkgs != "" then "-" + networkNixpkgs else "");


  configuration = let preConfiguration ={
  
    boot = {
      autoDetectRootDevice = true;
      readOnlyRoot = true;
      # The label used to identify the installation CD.
      rootLabel = "NIXOS";
      extraTTYs = [] ++ (lib.optional manualEnabled 7) ++
        (lib.optional rogueEnabled 8);
      inherit kernel;
      initrd = {
        extraKernelModules = extraInitrdKernelModules;
      };
      kernelModules = bootKernelModules;
    };
    
    services = {
    
      sshd = {
        enable = sshdEnabled;
      };
      
      xserver = {
        enable = false;
      };

      extraJobs = [
        # Unpack the NixOS/Nixpkgs sources to /etc/nixos.
        { name = "unpack-sources";
          job = "
            start on startup
            script
              export PATH=${pkgs.gnutar}/bin:${pkgs.bzip2}/bin:$PATH
              mkdir -p /etc/nixos/nixos
              tar xjf /nixos.tar.bz2 -C /etc/nixos/nixos
              tar xjf /nixpkgs.tar.bz2 -C /etc/nixos
              mv /etc/nixos/nixpkgs-* /etc/nixos/nixpkgs || true
              ln -sfn ../nixpkgs/pkgs /etc/nixos/nixos/pkgs
              chown -R root.root /etc/nixos
	      touch /etc/resolv.conf
            end script
          ";
        }] 
	
	++ 
      
        (lib.optional manualEnabled 
        # Show the NixOS manual on tty7.
        { name = "manual";
          job = "
            start on udev
            stop on shutdown
            respawn ${pkgs.w3m}/bin/w3m ${manual} < /dev/tty7 > /dev/tty7 2>&1
          ";
        })

	++

        (lib.optional rogueEnabled
        # Allow the user to do something useful on tty8 while waiting
        # for the installation to finish.
        { name = "rogue";
          job = "
            start on udev
            stop on shutdown
            respawn ${pkgs.rogue}/bin/rogue < /dev/tty8 > /dev/tty8 2>&1
          ";
        })

	++

	(lib.optional (addUsers != [])
	# Set empty passwords
	{
		name = "clear-passwords";
		job = '' 
                  start on startup
                  script 
                        for i in ${lib.concatStringsSep " " addUsers}; do
                            echo | ${pkgs.pwdutils}/bin/passwd --stdin $i
                        done
                  end script
		'';
	})
      ;

      # And a background to go with that.
      ttyBackgrounds = {
        specificThemes = []
	++
	  (lib.optional manualEnabled
          { tty = 7;
            # Theme is GPL according to http://kde-look.org/content/show.php/Green?content=58501.
            theme = pkgs.fetchurl {
              url = http://www.kde-look.org/CONTENT/content-files/58501-green.tar.gz;
              sha256 = "0sdykpziij1f3w4braq8r8nqg4lnsd7i7gi1k5d7c31m2q3b9a7r";
            };
          })
	++
	  (lib.optional rogueEnabled 
          { tty = 8;
            theme = pkgs.fetchurl {
              url = http://www.bootsplash.de/files/themes/Theme-GNU.tar.bz2;
              md5 = "61969309d23c631e57b0a311102ef034";
            };
          })
        ;
      };

      mingetty = {
        helpLine = ''
        
          Log in as "root" with an empty password. 
        ''
	+(if addUsers != [] then '' These users also have empty passwords:
	${lib.concatStringsSep " " addUsers }
	'' else "")
	+(if manualEnabled then " Press <Alt-F7> for help." else "");
      };
      
    };

    fonts = {
      enableFontConfig = fontConfigEnabled;
    };
    
    installer = {
      nixpkgsURL = 
      (if networkNixpkgs != "" then http://nix.cs.uu.nl/dist/nix/ + nixpkgsRel
        else file:///mnt/ );
    };

    security = {
      sudo = {
        enable = sudoEnable;
      };
    };
 
    environment = {
      extraPackages = if cleanStart then pkgs:[] else pkgs: [
        pkgs.vim
        pkgs.subversion # for nixos-checkout
        pkgs.w3m # needed for the manual anyway
      ] ++ (packages pkgs);
      checkConfigurationOptions = true;
      cleanStart = cleanStart;
    };

    users = {
      extraUsers = map userEntry addUsers;
    };
 
  }; in preConfiguration // (arbitraryOverrides preConfiguration);

  configurations = [{
    inherit configuration;
    suffix = "";
  }] ++ (configList configuration);
  systemPacks = map systemPackBuilder configurations;

  system = (builtins.head systemPacks).system; /* I hope this is unneeded */
  pkgs = system.pkgs; /* Nothing non-fixed should be built from it */


  # The NixOS manual, with a backward compatibility hack for Nix <=
  # 0.11 (you won't get the manual).
  manual =
    if builtins ? unsafeDiscardStringContext
    then "${import ../doc/manual}/manual.html"
    else pkgs.writeText "dummy-manual" "Manual not included in this build!";


  # Since the CD is read-only, the mount points must be on disk.
  cdMountPoints = pkgs.runCommand "mount-points" {} "
    ensureDir $out
    cd $out
    mkdir proc sys tmp etc dev var mnt nix nix/var root bin ${if addUsers != "" then "home" else ""}
    touch $out/${configuration.boot.rootLabel}
  ";


  # We need a copy of the Nix expressions for Nixpkgs and NixOS on the
  # CD.  We put them in a tarball because accessing that many small
  # files from a slow device like a CD-ROM takes too long.
  makeTarball = tarName: input: pkgs.runCommand "tarball" {inherit tarName;} "
    ensureDir $out
    (cd ${input} && tar cvfj $out/${tarName} . \\
      --exclude '*~' \\
      --exclude 'pkgs' --exclude 'result')
  ";

  makeNixPkgsTarball = tarName: input: ((pkgs.runCommand "tarball-nixpkgs" {inherit tarName;} "
    ensureDir $out
    (cd ${input}/.. && tar cvfj $out/${tarName} nixpkgs \\
      --exclude '*~' \\
      --exclude 'result')
  ")+"/${tarName}");


  
  # Put the current directory in a tarball (making sure to filter
  # out crap like the .svn directories).
  nixosTarball =
    let filter = name: type:
      let base = baseNameOf (toString name);
      in base != ".svn" && base != "result";
    in
      makeTarball "nixos.tar.bz2" (builtins.filterSource filter ./..);


  # Get a recent copy of Nixpkgs.
  nixpkgsTarball = if networkNixpkgs != "" then  pkgs.fetchurl {
    url = configuration.installer.nixpkgsURL + "/" + nixpkgsRel + ".tar.bz2";
    md5 = "6a793b877e2a4fa79827515902e1dfd8";
  } else makeNixPkgsTarball "nixpkgs.tar.bz2" "/etc/nixos/nixpkgs";


  # The configuration file for Grub.
  grubCfg = pkgs.writeText "menu.lst" (''
    default 0
    timeout 10
    splashimage /boot/background.xpm.gz
  ''+
  (lib.concatStrings (map systemPackGrubEntry systemPacks))
  + (if includeMemtest then
  ''

    title Memtest86+
      kernel /boot/memtest.bin
  '' else ""));


  # Create an ISO image containing the Grub boot loader, the kernel,
  # the initrd produced above, and the closure of the stage 2 init.
  rescueCD = import ../helpers/make-iso9660-image.nix {
    inherit (pkgs) stdenv perl cdrkit;
    isoName = "nixos-${platform}.iso";

    # Single files to be copied to fixed locations on the CD.
    contents = lib.uniqList {inputList =
    [
      { source = "${pkgs.grub}/lib/grub/i386-pc/stage2_eltorito";
        target = "boot/grub/stage2_eltorito";
      }
      { source = grubCfg;
        target = "boot/grub/menu.lst";
      }]
      ++ 
      (lib.concatLists (map systemPackInstallRootList systemPacks))
      ++
      [{ source = system.config.boot.grubSplashImage;
        target = "boot/background.xpm.gz";
      }
      { source = cdMountPoints;
        target = "/";
      }
      { source = nixosTarball + "/" + nixosTarball.tarName;
        target = "/" + nixosTarball.tarName;
      }
      { source = nixpkgsTarball;
        target = "/nixpkgs.tar.bz2";
      }
    ]
    ++
    (lib.optional includeMemtest 
      { source = pkgs.memtest86 + "/memtest.bin";
        target = "boot/memtest.bin";
      }
    )
    ;};

    # Closures to be copied to the Nix store on the CD.
    storeContents = lib.uniqListExt {
    	inputList= lib.concatLists 
		(map systemPackInstallClosures systemPacks);
	getter = x : x.object.drvPath;
	compare = lib.eqStrings;
    };

    buildStoreContents = lib.uniqList {inputList=([]
    ++
    (if includeBuildDeps then lib.concatLists 
    	(map systemPackInstallBuildClosure systemPacks)
	else [])
    );};
    
    bootable = true;
    bootImage = "boot/grub/stage2_eltorito";
  };

}
