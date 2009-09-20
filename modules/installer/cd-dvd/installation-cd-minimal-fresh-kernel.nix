# This module defines a small NixOS installation CD.  It does not
# contain any graphical stuff.

{config, pkgs, ...}:

rec {
  require = [./installation-cd-base.nix];

  installer.configModule = "./nixos/modules/installer/cd-dvd/installation-cd-minimal.nix";

  # Don't include X libraries.
  environment.noXlibs = true;

  # Most users will download it anyway
  security.sudo.enable = true;

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
    "iso9660" "loop" "squashfs"
    ];
  boot.initrd.allowMissing = true;

  environment.systemPackages = with pkgs; [
    klibc dmraid cryptsetup ccrypt 
    utillinuxCurses ddrescue testdisk
    pciutils sdparm hdparm usbutils
    btrfsProgs xfsProgs jfsUtils jfsrec
    wpa_supplicant iproute 
    manpages openssh openssl ncat socat
    fuse ntfs3g gnupg gnupg2
    patch which diffutils gcc binutils bc file
    gnused gnumake ncurses gnugrep findutils ed
    screen bvi joe nvi dar xz lsof
    unrar unzip zip lzma cpio 
    ];
}
