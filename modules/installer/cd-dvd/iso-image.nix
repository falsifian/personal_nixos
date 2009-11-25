# This module creates a bootable ISO image containing the given NixOS
# configuration.  The derivation for the ISO image will be placed in
# config.system.build.isoImage.

{ config, pkgs, ... }:

with pkgs.lib;

let

  options = {

    isoImage.isoName = mkOption {
      default = "cd.iso";
      description = ''
        Name of the generated ISO image file.
      '';
    };

    isoImage.compressImage = mkOption {
      default = false;
      description = ''
        Whether the ISO image should be compressed using
        <command>bzip2</command>.
      '';
    };

    isoImage.volumeID = mkOption {
      default = "NIXOS_BOOT_CD";
      description = ''
        Specifies the label or volume ID of the generated ISO image.
        Note that the label is used by stage 1 of the boot process to
        mount the CD, so it should be reasonably distinctive.
      '';
    };

    isoImage.contents = mkOption {
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

    isoImage.storeContents = mkOption {
      example = [pkgs.stdenv];
      description = ''
        This option lists additional derivations to be included in the
        Nix store in the generated ISO image.
      '';
    };

  };


  # The Grub image.
  grubImage = pkgs.runCommand "grub_eltorito" {}
    ''
      ${pkgs.grub2}/bin/grub-mkimage -o tmp biosdisk iso9660 help linux linux16 sh chain gfxterm vbe png jpeg
      cat ${pkgs.grub2}/lib/grub/*/cdboot.img tmp > $out
    ''; # */


  # The configuration file for Grub.
  grubCfg = 
    ''
      set default=0
      set timeout=10

      if loadfont /boot/grub/unicode.pf2; then
        set gfxmode=640x480
        insmod gfxterm
        insmod vbe
        terminal_output.gfxterm

        insmod png
        if background_image /boot/grub/splash.png; then
          set color_normal=white/black
          set color_highlight=black/white
        else
          set menu_color_normal=cyan/blue
          set menu_color_highlight=white/blue
        fi
        
      fi

      ${config.boot.loader.grub.extraEntries}
    '';
  
in

{
  require = options;

  boot.loader.grub.version = 2;

  # Don't build the GRUB menu builder script, since we don't need it
  # here and it causes a cyclic dependency.
  boot.loader.grub.enable = false;

  # !!! Hack - attributes expected by other modules.
  system.build.menuBuilder = "true";
  system.boot.loader.kernelFile = "vmlinuz";
  environment.systemPackages = [ pkgs.grub2 ];

  # In stage 1 of the boot, mount the CD/DVD as the root FS by label
  # so that we don't need to know its device.
  fileSystems =
    [ { mountPoint = "/";
        label = config.isoImage.volumeID;
      }
      { mountPoint = "/nix/store";
        fsType = "squashfs";
        device = "/nix-store.squashfs";
        options = "loop";
        neededForBoot = true;
      }
    ];

  # We need squashfs in the initrd to mount the compressed Nix store,
  # and aufs to make the root filesystem appear writable.
  boot.extraModulePackages = (optional 
    (! config.boot.kernelPackages.kernel.features ? aufs) 
    config.boot.kernelPackages.aufs);
  boot.initrd.extraKernelModules = ["aufs" "squashfs"];

  # Tell stage 1 of the boot to mount a tmpfs on top of the CD using
  # AUFS.  !!! It would be nicer to make the stage 1 init pluggable
  # and move that bit of code here.
  boot.isLiveCD = true;

  # Closures to be copied to the Nix store on the CD, namely the init
  # script and the top-level system configuration directory.
  isoImage.storeContents =
    [ config.system.build.bootStage2
      config.system.build.toplevel
    ];

  # Create the squashfs image that contains the Nix store.
  system.build.squashfsStore = import ../../../lib/make-squashfs.nix {
    inherit (pkgs) stdenv squashfsTools perl pathsFromGraph;
    storeContents = config.isoImage.storeContents;
  };

  # Individual files to be included on the CD, outside of the Nix
  # store on the CD.
  isoImage.contents =
    [ { source = grubImage;
        target = "/boot/grub/grub_eltorito";
      }
      { source = pkgs.writeText "grub.cfg" grubCfg;
        target = "/boot/grub/grub.cfg";
      }
      { source = config.boot.kernelPackages.kernel + "/vmlinuz";
        target = "/boot/vmlinuz";
      }
      { source = config.system.build.initialRamdisk + "/initrd";
        target = "/boot/initrd";
      }
      { source = "${pkgs.grub2}/share/grub/unicode.pf2";
        target = "/boot/grub/unicode.pf2";
      }
      { source = config.boot.loader.grub.splashImage;
        target = "/boot/grub/splash.png";
      }
      { source = config.system.build.squashfsStore;
        target = "/nix-store.squashfs";
      }
      { # Quick hack: need a mount point for the store.
        source = pkgs.runCommand "empty" {} "ensureDir $out";
        target = "/nix/store";
      }
    ];

  # The Grub menu.
  boot.loader.grub.extraEntries =
    ''
      menuentry "Boot from hard disk" {
        set root=(hd0)
        chainloader +1
      }
    
      menuentry "NixOS Installer / Rescue" {
        linux /boot/vmlinuz init=${config.system.build.bootStage2} systemConfig=${config.system.build.toplevel} ${toString config.boot.kernelParams}
        initrd /boot/initrd
      }
    '';

  # Create the ISO image.
  system.build.isoImage = import ../../../lib/make-iso9660-image.nix {
    inherit (pkgs) stdenv perl cdrkit pathsFromGraph;
    
    inherit (config.isoImage) isoName compressImage volumeID contents;

    bootable = true;
    bootImage = "/boot/grub/grub_eltorito";
  };

  boot.postBootCommands =
    ''
      # After booting, register the contents of the Nix store on the
      # CD in the Nix database in the tmpfs.
      ${config.environment.nix}/bin/nix-store --load-db < /nix/store/nix-path-registration

      # nixos-rebuild also requires a "system" profile and an
      # /etc/NIXOS tag.
      touch /etc/NIXOS
      ${config.environment.nix}/bin/nix-env -p /nix/var/nix/profiles/system --set /var/run/current-system
    '';
}
