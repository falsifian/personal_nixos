# This module defines a small NixOS installation CD.  It does not
# contain any graphical stuff.

{config, pkgs, ...}:

rec {
  require = [./installation-cd-base.nix];

  installer.configModule = "./nixos/modules/installer/cd-dvd/installation-cd-minimal.nix";

  # Don't include X libraries.
  services.sshd.forwardX11 = false;
  services.dbus.enable = false; # depends on libX11
  services.hal.enable = false; # depends on dbus
  fonts.enableFontConfig = false;
  fonts.enableCoreFonts = false;

  # Use Linux 2.6.31-zen2 (with aufs2).
  boot.kernelPackages = pkgs.kernelPackages_2_6_31_zen2;

  # We need squashfs and aufs. Zen Linux Kernel contains kernel side.
  boot.initrd.extraUtilsCommands = ''
    cp ${config.boot.kernelPackages.aufs2Utils}/sbin/mount.aufs $out/bin
    cp ${config.boot.kernelPackages.aufs2Utils}/sbin/umount.aufs $out/bin
    mkdir -p $out/var/run/current-system/sw
    ln -s /bin "$out/var/run/current-system/sw/sbin"
  '';

  boot.initrd.extraKernelModules = [
    "i8042" "pcips2" "serio" "mousedev" "evdev" "psmouse" "sermouse"
    "synaptics_i2c" "unix" "usbhid" "uhci_hcd" "ehci_hcd" "ohci_hcd" 
    "atkbd" "xtkbd" 
    # CD part
    "iso9660" "loop" "squashfs"
    ];
  boot.initrd.allowMissing = true;

  environment.systemPackages = with pkgs; [
    klibc 

    dmraid

    cryptsetup ccrypt 

    utillinuxCurses ddrescue testdisk
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
    dar p7zip xz lrzip rzip lzop
    lsof
    gcc gnused gnumake ncurses gnugrep findutils ed
    ];
}
