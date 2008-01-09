let

  configFileName =
    let env = builtins.getEnv "NIXOS_CONFIG"; in
    if env == "" then /etc/nixos/configuration.nix else env;

  system = import system/system.nix {configuration = import configFileName; 
    inherit configFileName; };

in

{ inherit (system)
    activateConfiguration
    bootStage1
    bootStage2
    etc
    extraUtils
    grubMenuBuilder
    initialRamdisk
    kernel
    nix
    nixosCheckout
    nixosInstall
    nixosRebuild
    system
    systemPath
    config
    ;

  nixFallback = system.nix;

  manifests = system.config.installer.manifests; # exported here because nixos-rebuild uses it

  upstartJobsCombined = system.upstartJobs;

  # Make it easier to build individual Upstart jobs (e.g., "nix-build
  # /etc/nixos/nixos -A upstartJobs.xserver").  
  upstartJobs = { recurseForDerivations = true; } //
    builtins.listToAttrs (map (job:
      { name = if job ? jobName then job.jobName else job.name; value = job; }
    ) system.upstartJobs.jobs);

}
