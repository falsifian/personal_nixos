# This module creates a bootable ISO image containing the given NixOS
# configuration.  The derivation for the ISO image will be placed in
# config.system.build.isoImage.

{config, pkgs, ...}:

let

  options = {

    isoImage.isoName = pkgs.lib.mkOption {
      default = "cd.iso";
      description = ''
        Name of the generated ISO image file.
      '';
    };

    isoImage.compressImage = pkgs.lib.mkOption {
      default = false;
      description = ''
        Whether the ISO image should be compressed using
        <command>bzip2</command>.
      '';
    };

    isoImage.volumeID = pkgs.lib.mkOption {
      default = "NIXOS_BOOT_CD";
      description = ''
        Specifies the label or volume ID of the generated ISO image.
        Note that the label is used by stage 1 of the boot process to
        mount the CD, so it should be reasonably distinctive.
      '';
    };

    isoImage.contents = pkgs.lib.mkOption {
      example =
        [ { source = pkgs.memtest86 + "/memtest.bin";
            target = "boot/memtest.bin";
          }
        ];
      description = ''
        This option lists files to be copied to fixed locations in the
        generated ISO image.
      '';
    };

    isoImage.storeContents = pkgs.lib.mkOption {
      example =
        [ { object = pkgs.stdenv;
            symlink = "/stdenv";
          }
        ];
      description = ''
        This option lists additional derivations to be included in the
        Nix store in the generated ISO image.
      '';
    };

  };


  # The configuration file for Grub.
  grubCfg = 
    ''
      default 0
      timeout 10
      splashimage /boot/background.xpm.gz

      ${config.boot.extraGrubEntries}
    '';
  
in

{
  require = options;

  # In stage 1 of the boot, mount the CD/DVD as the root FS by label
  # so that we don't need to know its device.
  fileSystems =
    [ { mountPoint = "/";
        label = config.isoImage.volumeID;
      }
    ];

  # We need AUFS in the initrd to make the CD appear writable.
  boot.extraModulePackages = [config.boot.kernelPackages.aufs];
  boot.initrd.extraKernelModules = ["aufs"];

  # Tell stage 1 of the boot to mount a tmpfs on top of the CD using
  # AUFS.  !!! It would be nicer to make the stage 1 init pluggable
  # and move that bit of code here.
  boot.isLiveCD = true;

  # Individual files to be included on the CD, outside of the Nix
  # store on the CD.
  isoImage.contents =
    [ { source = "${pkgs.grub}/lib/grub/${if pkgs.stdenv.system == "i686-linux" then "i386-pc" else "x86_64-unknown"}/stage2_eltorito";
        target = "/boot/grub/stage2_eltorito";
      }
      { source = pkgs.writeText "menu.lst" grubCfg;
        target = "/boot/grub/menu.lst";
      }
      { source = config.boot.kernelPackages.kernel + "/vmlinuz";
        target = "/boot/vmlinuz";
      }
      { source = config.system.build.initialRamdisk + "/initrd";
        target = "/boot/initrd";
      }
      { source = config.boot.grubSplashImage;
        target = "/boot/background.xpm.gz";
      }
    ];

  # Closures to be copied to the Nix store on the CD, namely the init
  # script and the top-level system configuration directory.
  isoImage.storeContents =
    [ { object = config.system.build.bootStage2;
        symlink = "/init";
      }
      { object = config.system.build.system;
        symlink = "/system";
      }
    ];

  # The Grub menu.
  boot.extraGrubEntries =
    ''
      title Boot from hard disk
        root (hd0)
        chainloader +1
    
      title NixOS Installer / Rescue
        kernel /boot/vmlinuz init=/init ${toString config.boot.kernelParams}
        initrd /boot/initrd
    '';

  # Create the ISO image.
  system.build.isoImage = import ../../../lib/make-iso9660-image.nix {
    inherit (pkgs) stdenv perl cdrkit pathsFromGraph;
    
    inherit (config.isoImage) isoName compressImage volumeID contents storeContents;

    bootable = true;
    bootImage = "/boot/grub/stage2_eltorito";
  };

  # After booting, register the contents of the Nix store on the CD in
  # the Nix database in the tmpfs.
  boot.postBootCommands =
    ''
      ${config.environment.nix}/bin/nix-store --load-db < /nix-path-registration
      rm /nix-path-registration
    '';
}
