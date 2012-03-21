{ config, pkgs, ... }:

with pkgs.lib;

let

  inInitrd = any (fs: fs == "nfs") config.boot.initrd.supportedFilesystems;

  nfsStateDir = "/var/lib/nfs";

  rpcMountpoint = "${nfsStateDir}/rpc_pipefs";

  idmapdConfFile = {
    target = "idmapd.conf";
    source = pkgs.writeText "idmapd.conf" ''
      [General]
      Pipefs-Directory = ${rpcMountpoint}
      ${optionalString (config.networking.domain != "")
        "Domain = ${config.networking.domain}"}

      [Mapping]
      Nobody-User = nobody
      Nobody-Group = nogroup

      [Translation]
      Method = nsswitch
    '';
  };

in

{

  ###### interface

  options = {

    services.nfs.client.enable = mkOption {
      default = any (fs: fs.fsType == "nfs" || fs.fsType == "nfs4") config.fileSystems;
      description = ''
        Whether to enable support for mounting NFS filesystems.
      '';
    };

  };


  ###### implementation

  config = mkIf config.services.nfs.client.enable {

    services.portmap.enable = true;
    
    system.fsPackages = [ pkgs.nfsUtils ];

    boot.initrd.kernelModules = mkIf inInitrd [ "nfs" ];

    boot.initrd.extraUtilsCommands = mkIf inInitrd
      ''
        # !!! Uh, why don't we just install mount.nfs?
        cp -v ${pkgs.klibc}/lib/klibc/bin.static/nfsmount $out/bin
      '';

    environment.etc = singleton idmapdConfFile;

    jobs.statd =
      { description = "Kernel NFS server - Network Status Monitor";

        path = [ pkgs.nfsUtils pkgs.sysvtools pkgs.utillinux ];

        stopOn = ""; # needed during shutdown

        preStart =
          ''
            ensure portmap
            mkdir -p ${nfsStateDir}/sm
            mkdir -p ${nfsStateDir}/sm.bak
            sm-notify -d
          '';

        daemonType = "fork";

        exec = "rpc.statd --no-notify";
      };

    jobs.idmapd =
      { description = "Kernel NFS server - ID Map Daemon";

        path = [ pkgs.nfsUtils pkgs.sysvtools pkgs.utillinux ];

        stopOn = "starting shutdown";

        preStart =
          ''
            ensure portmap
            mkdir -p ${rpcMountpoint}
            mount -t rpc_pipefs rpc_pipefs ${rpcMountpoint}
          '';

        postStop =
          ''
            umount ${rpcMountpoint}
          '';

        daemonType = "fork";

        exec = "rpc.idmapd";
      };

  };
}
