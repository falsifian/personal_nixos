{
  require = [
    ../system/assertion.nix
    ../system/nixos-environment.nix
    ../system/nixos-installer.nix
    ../upstart-jobs/cron/locate.nix
    ../upstart-jobs/filesystems.nix
    ../upstart-jobs/kbd.nix
    ../upstart-jobs/ldap
    ../upstart-jobs/lvm.nix
    ../upstart-jobs/network-interfaces.nix
    ../upstart-jobs/pcmcia.nix
    ../upstart-jobs/swap.nix
    ../upstart-jobs/swraid.nix
    ../upstart-jobs/tty-backgrounds.nix
  ];
}
