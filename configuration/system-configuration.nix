let

  # The root device.
  rootDevice = "/dev/hda1";

  # The device on which GRUB should be installed (leave empty if you
  # don't want GRUB to be installed).
  grubDevice = "/dev/hda";

  # Build boot scripts.
  bootEnv = import ./boot-environment.nix {
    autoDetectRootDevice = false;
    inherit rootDevice;
    stage2Init = ""; # Passed on the command line via Grub.
    readOnlyRoot = false;
  };

  # Extra kernel command line arguments.
  extraKernelParams = [
    "selinux=0"
    "apm=on"
    "acpi=on"
    "vga=0x317"
    "console=tty1"
    "splash=verbose"
  ];

in

with bootEnv;
  
rec {

  inherit upstartJobs;


  systemConfiguration = pkgs.stdenv.mkDerivation {
    name = "system-configuration";
    builder = ./system-configuration.sh;
    inherit (pkgs) grub coreutils gnused gnugrep diffutils findutils;
    inherit grubDevice;
    inherit bootStage2;
    inherit activateConfiguration;
    inherit grubMenuBuilder;
    kernel = pkgs.kernel + "/vmlinuz";
    initrd = initialRamdisk + "/initrd";
    inherit extraKernelParams;
  };


  grubMenuBuilder = pkgs.genericSubstituter {
    src = ../installer/grub-menu-builder.sh;
    isExecutable = true;
    inherit (pkgs) bash;
  };


}
