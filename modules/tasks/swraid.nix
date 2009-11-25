{ config, pkgs, ... }:

###### implementation

let

  tempConf = "/var/run/mdadm.conf";
  modprobe = config.system.sbin.modprobe;
  inherit (pkgs) mdadm;

in
  
{

  jobs.swraid =
    { startOn = "started udev or new-devices";
      
      script =
        ''
          # Load the necessary RAID personalities.
          # !!! hm, doesn't the kernel load these automatically?
          for mod in raid0 raid1 raid5; do
              ${modprobe}/sbin/modprobe $mod || true
          done
      
          # Scan /proc/partitions for RAID devices.
          ${mdadm}/sbin/mdadm --examine --brief --scan -c partitions > ${tempConf}
          
          if ! test -s ${tempConf}; then exit 0; fi
      
          # Activate each device found.
          ${mdadm}/sbin/mdadm --assemble -c ${tempConf} --scan
      
          initctl emit -n new-devices
        '';

      task = true;        
    };

}
