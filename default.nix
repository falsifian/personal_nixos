{ configuration ? import ./lib/from-env.nix "NIXOS_CONFIG" /etc/nixos/configuration.nix
}:

let
  
  eval = import ./lib/eval-config.nix { modules = [ configuration ]; };

  inherit (eval) config pkgs;

  vmConfig = (import ./lib/eval-config.nix {
    modules = [ configuration ./modules/virtualisation/qemu-vm.nix ];
  }).config;
    
in

{
  inherit eval config;

  system = config.system.build.toplevel;

  vm = vmConfig.system.build.vm;

  # The following are used by nixos-rebuild.
  nixFallback = pkgs.nixUnstable;
  manifests = config.installer.manifests;

  tests = config.tests;
}
