# This module contains the basic configuration for building a NixOS
# installation CD.

{config, pkgs, ...}:

let

  options = {

    system.nixosVersion = pkgs.lib.mkOption {
      default = "${builtins.readFile ../../../VERSION}";
      description = ''
        NixOS version number.
      '';
    };

    installer.configModule = pkgs.lib.mkOption {
      example = "./nixos/modules/installer/cd-dvd/installation-cd.nix";
      description = ''
        Filename of the configuration module that builds the CD
        configuration.  Must be specified to support reconfiguration
        in live CDs.
      '';
    };
  
  };


  # We need a copy of the Nix expressions for Nixpkgs and NixOS on the
  # CD.  We put them in a tarball because accessing that many small
  # files from a slow device like a CD-ROM takes too long.  !!! Once
  # we use squashfs, maybe we won't need this anymore.
  makeTarball = tarName: input: pkgs.runCommand "tarball" {inherit tarName;}
    ''
      ensureDir $out
      (cd ${input} && tar cvfj $out/${tarName} . \
        --exclude '*~' --exclude 'result')
    '';

  # Put the current directory in a tarball.
  nixosTarball = makeTarball "nixos.tar.bz2" (pkgs.lib.cleanSource ../../..);

  # Put Nixpkgs in a tarball.
  nixpkgsTarball = makeTarball "nixpkgs.tar.bz2" (pkgs.lib.cleanSource pkgs.path);


  # A dummy /etc/nixos/configuration.nix in the booted CD that
  # rebuilds the CD's configuration (and allows the configuration to
  # be modified, of course, providing a true live CD).  Problem is
  # that we don't really know how the CD was built - the Nix
  # expression language doesn't allow us to query the expression being
  # evaluated.  So we'll just hope for the best.
  dummyConfiguration = pkgs.writeText "configuration.nix"
    ''
      {config, pkgs, ...}:

      {
        require = [${config.installer.configModule}];

        # Add your own options below and run "nixos-rebuild switch".
        # E.g.,
        #   services.sshd.enable = true;
      }
    '';
  
  
in

{
  require =
    [ options
      ./iso-image.nix
      ./memtest.nix
      ../../../hardware/network/intel-3945abg.nix
    ];

  # ISO naming.
  isoImage.isoName = "nixos-${config.system.nixosVersion}-${pkgs.stdenv.system}.iso";
    
  isoImage.volumeID = "NIXOS_INSTALLATION_CD_${config.system.nixosVersion}";
  
  # Use Linux 2.6.29.
  boot.kernelPackages = pkgs.kernelPackages_2_6_29;

  # Show the manual.
  services.showManual.enable = true;

  # Let the user play Rogue on TTY 8 during the installation.
  services.rogue.enable = true;

  # Disable some other stuff we don't need.
  security.sudo.enable = false;

  # Include only the en_US locale.  This saves 75 MiB or so compared to
  # the full glibcLocales package.
  i18n.supportedLocales = ["en_US.UTF-8/UTF-8" "en_US/ISO-8859-1"];

  # Include some utilities that are useful for installing or repairing
  # the system.
  environment.systemPackages =
    [ pkgs.subversion # for nixos-checkout
      pkgs.w3m # needed for the manual anyway
      pkgs.testdisk # useful for repairing boot problems
      pkgs.mssys # for writing Microsoft boot sectors / MBRs
      pkgs.ntfsprogs # for resizing NTFS partitions
      pkgs.parted
      pkgs.sshfsFuse
    ];

  # The initrd has to contain any module that might be necessary for
  # mounting the CD/DVD.
  boot.initrd.extraKernelModules =
    [ # SATA/PATA support.
      "ahci"

      "ata_piix"

      "sata_inic162x" "sata_nv" "sata_promise" "sata_qstor"
      "sata_sil" "sata_sil24" "sata_sis" "sata_svw" "sata_sx4"
      "sata_uli" "sata_via" "sata_vsc"

      "pata_ali" "pata_amd" "pata_artop" "pata_atiixp"
      "pata_cs5520" "pata_cs5530" /* "pata_cs5535" */ "pata_efar"
      "pata_hpt366" "pata_hpt37x" "pata_hpt3x2n" "pata_hpt3x3"
      "pata_it8213" "pata_it821x" "pata_jmicron" "pata_marvell"
      "pata_mpiix" "pata_netcell" "pata_ns87410" "pata_oldpiix"
      "pata_pcmcia" "pata_pdc2027x" /* "pata_qdi" */ "pata_rz1000"
      "pata_sc1200" "pata_serverworks" "pata_sil680" "pata_sis"
      "pata_sl82c105" "pata_triflex" "pata_via"
      # "pata_winbond" <-- causes timeouts in sd_mod

      # SCSI support (incomplete).
      "3w-9xxx" "3w-xxxx" "aic79xx" "aic7xxx" "arcmsr" 

      # USB support, especially for booting from USB CD-ROM
      # drives.  Also include USB keyboard support for when
      # something goes wrong in stage 1.
      "ehci_hcd"
      "ohci_hcd"
      "uhci_hcd"
      "usbhid"
      "usb_storage"

      # Firewire support.  Not tested.
      "ohci1394" "sbp2"

      # Virtio (QEMU, KVM etc.) support.
      "virtio_net" "virtio_pci" "virtio_blk" "virtio_balloon"

      # Wait for SCSI devices to appear.
      "scsi_wait_scan"
    ];

  # nixos-install will do a pull from this channel to speed up the
  # installation.
  installer.nixpkgsURL = http://nixos.org/releases/nixpkgs/channels/nixpkgs-unstable;

  boot.postBootCommands =
    ''
      export PATH=${pkgs.gnutar}/bin:${pkgs.bzip2}/bin:$PATH

      # Provide a mount point for nixos-install.
      mkdir -p /mnt

      # Provide the NixOS/Nixpkgs sources in /etc/nixos.  This is required
      # for nixos-install.
      echo "unpacking the NixOS/Nixpkgs sources..."
      mkdir -p /etc/nixos/nixos
      tar xjf ${nixosTarball}/nixos.tar.bz2 -C /etc/nixos/nixos
      mkdir -p /etc/nixos/nixpkgs
      tar xjf ${nixpkgsTarball}/nixpkgs.tar.bz2 -C /etc/nixos/nixpkgs
      chown -R root.root /etc/nixos

      # Provide a configuration for the CD/DVD itself, to allow users
      # to run nixos-rebuild to change the configuration of the
      # running system on the CD/DVD.
      cp ${dummyConfiguration} /etc/nixos/configuration.nix
    '';

  # Some more help text.
  services.mingetty.helpLine =
    ''
        
      Log in as "root" with an empty password.  ${
        if config.services.xserver.enable then
          "Type `start xserver' to start\nthe graphical user interface."
        else ""
      }
    '';

  # To speed up installation a little bit, include the complete stdenv
  # in the Nix store on the CD.
  isoImage.storeContents = [pkgs.stdenv];
}
