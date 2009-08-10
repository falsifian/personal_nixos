{pkgs, config, ...}:

###### interface
let
  inherit (pkgs.lib) mkOption;

  options = {
    boot = {
      kernelPackages = mkOption {
        default = pkgs.kernelPackages;
        example = pkgs.kernelPackages_2_6_25;
        description = "
          This option allows you to override the Linux kernel used by
          NixOS.  Since things like external kernel module packages are
          tied to the kernel you're using, it also overrides those.
          This option is a function that takes Nixpkgs as an argument
          (as a convenience), and returns an attribute set containing at
          the very least an attribute <varname>kernel</varname>.
          Additional attributes may be needed depending on your
          configuration.  For instance, if you use the NVIDIA X driver,
          then it also needs to contain an attribute
          <varname>nvidia_x11</varname>.
        ";
      };

      kernelParams = mkOption {
        default = [
          "selinux=0"
          "apm=on"
          "acpi=on"
          "vga=0x317"
          "console=tty1"
          "splash=verbose"
        ];
        description = "
          The kernel parameters.  If you want to add additional
          parameters, it's best to set
          <option>boot.extraKernelParams</option>.
        ";
      };

      extraKernelParams = mkOption {
        default = [
        ];
        example = [
          "debugtrace"
        ];
        description = "
          Additional user-defined kernel parameters.
        ";
      };

      extraModulePackages = mkOption {
        default = [];
        # !!! example = [pkgs.aufs pkgs.nvidia_x11];
        description = ''
          A list of additional packages supplying kernel modules.
        '';
      };

      kernelModules = mkOption {
        default = [];
        description = "
          The set of kernel modules to be loaded in the second stage of
          the boot process.  That is, these modules are not included in
          the initial ramdisk, so they'd better not be required for
          mounting the root file system.  Add them to
          <option>boot.initrd.extraKernelModules</option> if they are.
        ";
      };

      initrd = {

        kernelModules = mkOption {
          default = [
            # Note: most of these (especially the SATA/PATA modules)
            # shouldn't be included by default since nixos-hardware-scan
            # detects them, but I'm keeping them for now for backwards
            # compatibility.
            
            # Some SATA/PATA stuff.        
            "ahci"
            "sata_nv"
            "sata_via"
            "sata_sis"
            "sata_uli"
            "ata_piix"
            "pata_marvell"
            
            # Standard SCSI stuff.
            "sd_mod"
            "sr_mod"
            
            # Standard IDE stuff.
            "ide_cd"
            "ide_disk"
            "ide_generic"
            
            # Filesystems.
            "ext3"
            
            # Support USB keyboards, in case the boot fails and we only have
            # a USB keyboard.
            "ehci_hcd"
            "ohci_hcd"
            "usbhid"

            # LVM.
            "dm_mod"
          ];
          description = "
            The set of kernel modules in the initial ramdisk used during the
            boot process.  This set must include all modules necessary for
            mounting the root device.  That is, it should include modules
            for the physical device (e.g., SCSI drivers) and for the file
            system (e.g., ext3).  The set specified here is automatically
            closed under the module dependency relation, i.e., all
            dependencies of the modules list here are included
            automatically.  If you want to add additional
            modules, it's best to set
            <option>boot.initrd.extraKernelModules</option>.
          ";
        };

        extraKernelModules = mkOption {
          default = [];
          description = "
            Additional kernel modules for the initial ramdisk.  These are
            loaded before the modules listed in
            <option>boot.initrd.kernelModules</option>, so they take
            precedence.
          ";
        };

      };
    };

    system.modulesTree = mkOption {
      internal = true;
      default = [];
      description = "
        Tree of kernel modules.  This includes the kernel, plus modules
        built outside of the kernel.  Combine these into a single tree of
        symlinks because modprobe only supports one directory.
      ";
      merge = pkgs.lib.mergeListOption;

      # Convert the list of path to only one path.
      apply = pkgs.aggregateModules;
    };

    system.sbin.modprobe = mkOption {
      # should be moved in module-init-tools
      internal = true;
      default = pkgs.writeTextFile {
        name = "modprobe";
        destination = "/sbin/modprobe";
        executable = true;
        text =
          ''
            #! ${pkgs.stdenv.shell}
            export MODULE_DIR=${config.system.modulesTree}/lib/modules
            exec ${pkgs.module_init_tools}/sbin/modprobe "$@"
          '';
      };
      description = ''
        Wrapper around modprobe that sets the path to the modules
        tree.
      '';
    };
  };
  
in

###### implementation
let
  kernelPackages = config.boot.kernelPackages;
  kernel = kernelPackages.kernel;
in

{
  require = [options];

  system.modulesTree = [ kernel ] ++ config.boot.extraModulePackages;

  # The Linux kernel >= 2.6.27 provides firmware.
  hardware.firmware = [ "${kernel}/lib/firmware" ];
}
