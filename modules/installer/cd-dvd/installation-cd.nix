# This module contains the configuration for the NixOS installation CD.

{config, pkgs, ...}:

let

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

in

{
  require =
    [ ./iso-image.nix
      ./memtest.nix
      ../../../hardware/network/intel-3945abg.nix
    ];

  # Use Linux 2.6.29.
  boot.kernelPackages = pkgs.kernelPackages_2_6_29;

  # Don't include X libraries.
  services.sshd.forwardX11 = false;
  fonts.enableFontConfig = false;

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

  # Provide the NixOS/Nixpkgs sources in /etc/nixos.  This is required
  # for nixos-install.
  boot.postBootCommands =
    ''
      export PATH=${pkgs.gnutar}/bin:${pkgs.bzip2}/bin:$PATH

      mkdir -p /mnt

      echo "unpacking the NixOS/Nixpkgs sources..."
      mkdir -p /etc/nixos/nixos
      tar xjf ${nixosTarball}/nixos.tar.bz2 -C /etc/nixos/nixos
      mkdir -p /etc/nixos/nixpkgs
      tar xjf ${nixpkgsTarball}/nixpkgs.tar.bz2 -C /etc/nixos/nixpkgs
      chown -R root.root /etc/nixos
    '';

  services.mingetty.helpLine =
    ''
        
      Log in as "root" with an empty password.
    '';
}
