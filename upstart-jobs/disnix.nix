args: with args;

let

cfg = config.services.disnix;

in
{
    name = "disnix";
        
    job = ''
      description "Disnix server"

      start on dbus
      stop on shutdown  
          
      respawn ${pkgs.bash}/bin/sh -c 'export PATH=/var/run/current-system/sw/bin:$PATH; export HOME=/root; export DISNIX_ACTIVATE_HOOK=${cfg.activateHook}; export DISNIX_DEACTIVATE_HOOK=${cfg.deactivateHook}; ${pkgs.disnix}/bin/disnix-service'
    '';
}
