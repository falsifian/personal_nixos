args: with args;

let

cfg = config.services.ejabberd;

in
{
    name = "ejabberd";
        
    job = ''
      description "EJabberd server"

      start on network-interface/started
      stop on network-interfaces/stop
    
      start script
            # Initialise state data
            mkdir -p ${cfg.logsDir}
            
            if ! test -d ${cfg.spoolDir}
            then
                cp -av ${pkgs.ejabberd}/var/lib/ejabberd /var/lib
            fi
	    
	    mkdir -p ${cfg.confDir}
	    sed -e 's|{hosts, \["localhost"\]}.|{hosts, \[${cfg.virtualHosts}\]}.|' ${pkgs.ejabberd}/etc/ejabberd/ejabberd.cfg > ${cfg.confDir}/ejabberd.cfg
      end script
      
      respawn ${pkgs.bash}/bin/sh -c 'export PATH=$PATH:${pkgs.ejabberd}/sbin; cd ~; ejabberdctl --logs ${cfg.logsDir} --spool ${cfg.spoolDir} --config ${cfg.confDir}/ejabberd.cfg start; sleep 1d'
      
      stop script
          ${pkgs.ejabberd}/sbin/ejabberdctl stop
      end script
    '';
}
