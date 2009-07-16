# This module defines a small NixOS installation CD.  It does not
# contain any graphical stuff.

{config, pkgs, ...}:

{
  require = [./installation-cd-base.nix];

  installer.configModule = "./nixos/modules/installer/cd-dvd/installation-cd-minimal.nix";

  # Don't include X libraries.
  services.sshd.forwardX11 = false;
  services.dbus.enable = false; # depends on libX11
  services.hal.enable = false; # depends on dbus
  fonts.enableFontConfig = false;
  fonts.enableCoreFonts = false;

  # Useful for rescue..
  environment.systemPackages = with pkgs; [
    utillinuxCurses ddrescue 
    pciutils sdparm hdparm hddtemp usbutils
    btrfsProgs xfsProgs jfsUtils jfsrec
    wpa_supplicant iproute 
    fuse ntfs3g smbfsFuse sshfsFuse
    manpages irssi elinks mcabber mutt openssh lftp 
    openssl ncat socat
    gnupg gnupg2
    patch which diffutils gcc binutils bc file
    screen
    bvi joe nvi 
    subversion16 monotone git darcs mercurial bazaar cvs
    unrar unzip zip lzma cabextract cpio 
    lsof
  ];

  boot.kernelPackages = pkgs.kernelPackages_2_6_31_rc2_old_i686;
  boot.initrd.extraKernelModules = ["evdev" "i8042" "pcips2" "serio"
    "sd_mod" "libata" "unix" "usbhid" "uhci_hcd" "atkbd" "xtkbd" "fbdev"
    "iso9660" "udf"];
  boot.kernelModules = ["fbcon" "radeonfb" "intelfb" "sisfb" "nvidiafb"
    "cirrusfb"];
  boot.kernelParams = [
      "selinux=0"
      "acpi=on"
      "apm=off"
      "console=tty1"
      "splash=verbose"
    ];

  services.ttyBackgrounds.enable = false;
}
