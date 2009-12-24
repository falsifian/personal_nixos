{ config, pkgs, ... }:

with pkgs.lib;

let

  inherit (pkgs) writeText openssh;

  cfg = config.services.nfsKernel;

  exports =
    if builtins.pathExists cfg.exports
    then cfg.exports
    else pkgs.writeText "exports" cfg.exports;

in

{

  ###### interface

  options = {
  
    services.nfsKernel = {

      enable = mkOption {
        default = false;
        description = ''
          Whether to enable the kernel's NFS server.
        '';
      };

      # !!! Why is this a file?  Why not a list of export entries?
      exports = mkOption {
        check = v: v != "/etc/exports"; # this won't work
        description = ''
          The file listing the directories to be exported.  See
          <citerefentry><refentrytitle>exports</refentrytitle>
          <manvolnum>5</manvolnum></citerefentry> for the format.
        '';
      };

      hostName = mkOption {
        default = null;
        description = ''
          Hostname or address on which NFS requests will be accepted.
          Default is all.  See the <option>-H</option> option in
          <citerefentry><refentrytitle>nfsd</refentrytitle>
          <manvolnum>8</manvolnum></citerefentry>.
        '';
      };
      
      nproc = mkOption {
        default = 8;
        description = ''
          Number of NFS server threads.  Defaults to the recommended value of 8.
        '';
      };

      createMountPoints = mkOption {
        default = false;
        description = "Whether to create the mount points in the exports file at startup time.";
      };
      
    };

  };


  ###### implementation

  config = mkIf config.services.nfsKernel.enable {

    assertions = singleton
      { assertion = config.services.portmap.enable;
        message = "Please enable portmap (services.portmap.enable) to use nfs-kernel.";
      };

    environment.etc = singleton
      { source = exports;
        target = "exports";
      };

    jobs.nfs_kernel_exports =
      { name = "nfs-kernel-exports";
      
        description = "Kernel NFS server";

        startOn = "started network-interfaces";
        stopOn = "stopping network-interfaces";

        preStart =
          ''
            export PATH=${pkgs.nfsUtils}/sbin:$PATH
            mkdir -p /var/lib/nfs
            ${config.system.sbin.modprobe}/sbin/modprobe nfsd || true

            ${optionalString cfg.createMountPoints
              ''
                # create export directories:
                # skip comments, take first col which may either be a quoted
                # "foo bar" or just foo (-> man export)
                sed '/^#.*/d;s/^"\([^"]*\)".*/\1/;t;s/[ ].*//' ${exports} \
                | xargs -d '\n' mkdir -p
	      ''
            }
	    	  
            # exports file is ${exports}
            # keep this comment so that this job is restarted whenever exports changes!
            exportfs -ra
          '';
      };

    jobs.nfs_kernel_nfsd =
      { name = "nfs-kernel-nfsd";

        description = "Kernel NFS server";

        startOn = "started nfs-kernel-exports and started portmap";
        stopOn = "stopping nfs-kernel-exports";

        exec = "${pkgs.nfsUtils}/sbin/rpc.nfsd ${if cfg.hostName != null then "-H ${cfg.hostName}" else ""} ${builtins.toString cfg.nproc}";
      };

    jobs.nfs_kernel_mountd =
      { name = "nfs-kernel-mountd";

        description = "Kernel NFS server - mount daemon";

        startOn = "started nfs-kernel-nfsd and started portmap";
        stopOn = "stopping nfs-kernel-exports";

        exec = "${pkgs.nfsUtils}/sbin/rpc.mountd -F -f ${exports}";
      };

    jobs.nfs_kernel_statd =
      { name = "nfs-kernel-statd";
      
        description = "Kernel NFS server - Network Status Monitor";
      
        startOn = "started nfs-kernel-nfsd and started portmap";
        stopOn = "stopping nfs-kernel-exports";

        preStart =
          ''	
            mkdir -p /var/lib/nfs
          '';

        exec = "${pkgs.nfsUtils}/sbin/rpc.statd -F";
      };
      
  };
  
}
