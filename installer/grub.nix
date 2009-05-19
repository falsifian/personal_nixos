{pkgs, config, ...}:

###### interface
let
  inherit (pkgs.lib) mkOption;

  options = {
    boot = {

      grubDevice = mkOption {
        default = "";
        example = "/dev/hda";
        description = "
          The device on which the boot loader, Grub, will be installed.
          If empty, Grub won't be installed and it's your responsibility
          to make the system bootable.
        ";
      };

      bootMount = mkOption {
        default = "";
        example = "(hd0,0)";
        description = "
          If the system partition may be wiped on reinstall, it is better
          to have /boot on a small partition. To do it, we need to explain
          to GRUB where the kernels live. Specify the partition here (in 
          GRUB notation.
        ";
      };

      configurationName = mkOption {
        default = "";
        example = "Stable 2.6.21";
        description = "
          Grub entry name instead of default.
        ";
      };

      extraGrubEntries = mkOption {
        default = "";
        example = "
          title Windows
            chainloader (hd0,1)+1
        ";
        description = "
          Any additional entries you want added to the Grub boot menu.
        ";
      };

      extraGrubEntriesBeforeNixos = mkOption {
        default = false;
        description = "
          Wheter extraGrubEntries are put before the Nixos-default option
        ";
      };

      grubSplashImage = mkOption {
        default = pkgs.fetchurl {
          url = http://www.gnome-look.org/CONTENT/content-files/36909-soft-tux.xpm.gz;
          sha256 = "14kqdx2lfqvh40h6fjjzqgff1mwk74dmbjvmqphi6azzra7z8d59";
        };
        example = null;
        description = "
          Background image used for Grub.  It must be a 640x480,
          14-colour image in XPM format, optionally compressed with
          <command>gzip</command> or <command>bzip2</command>.  Set to
          <literal>null</literal> to run Grub in text mode.
        ";
      };

      configurationLimit = mkOption {
        default = 100;
        example = 120;
        description = "
          Maximum of configurations in boot menu. GRUB has problems when
          there are too many entries.
        ";
      };

    };
  };
in


###### implementation
let

  grubMenuBuilder = pkgs.substituteAll {
    src = ../installer/grub-menu-builder.sh;
    isExecutable = true;
    inherit (pkgs) bash;
    path = [pkgs.coreutils pkgs.gnused pkgs.gnugrep];
    inherit (config.boot) copyKernels extraGrubEntries extraGrubEntriesBeforeNixos
      grubSplashImage bootMount configurationLimit;
  };
in

{
  require = [
    options

    # config.system.build
    ../system/system-options.nix
  ];

  system = {
    build = {
      inherit grubMenuBuilder;
    };
  };

  # and many other things that have to be moved inside this file.
}
