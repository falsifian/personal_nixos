{ config, pkgs, ... }:

with pkgs.lib;

let

  fstab = pkgs.writeText "fstab"
    ''
      # This is a generated file.  Do not edit!

      # Filesystems.
      ${flip concatMapStrings config.fileSystems (fs:
          (if fs.device != null then fs.device else "/dev/disk/by-label/${fs.label}")
          + " " + fs.mountPoint
          + " " + fs.fsType
          + " " + fs.options
          + " 0"
          + " " + (if fs.fsType == "none" || fs.noCheck then "0" else
                   if fs.mountPoint == "/" then "1" else "2")
          + "\n"
      )}

      # Swap devices.
      ${flip concatMapStrings config.swapDevices (sw:
           "${sw.device} none swap\n"
      )}
    '';

in
    
{

  ###### interface

  options = {

    fileSystems = mkOption {
      example = [
        { mountPoint = "/";
          device = "/dev/hda1";
        }
        { mountPoint = "/data";
          device = "/dev/hda2";
          fsType = "ext3";
          options = "data=journal";
        }
        { mountPoint = "/bigdisk";
          label = "bigdisk";
        }
      ];

      description = ''
        The file systems to be mounted.  It must include an entry for
        the root directory (<literal>mountPoint = \"/\"</literal>).  Each
        entry in the list is an attribute set with the following fields:
        <literal>mountPoint</literal>, <literal>device</literal>,
        <literal>fsType</literal> (a file system type recognised by
        <command>mount</command>; defaults to
        <literal>\"auto\"</literal>), and <literal>options</literal>
        (the mount options passed to <command>mount</command> using the
        <option>-o</option> flag; defaults to <literal>\"defaults\"</literal>).

        Instead of specifying <literal>device</literal>, you can also
        specify a volume label (<literal>label</literal>) for file
        systems that support it, such as ext2/ext3 (see <command>mke2fs
        -L</command>).

        <literal>autocreate</literal> forces <literal>mountPoint</literal> to be created with
        <command>mkdir -p</command> .
      '';

      type = types.nullOr (types.list types.optionSet);

      options = {

        mountPoint = mkOption {
          example = "/mnt/usb";
          type = types.uniq types.string;
          description = "Location of the mounted the file system.";
        };

        device = mkOption {
          default = null;
          example = "/dev/sda";
          type = types.uniq (types.nullOr types.string);
          description = "Location of the device.";
        };

        label = mkOption {
          default = null;
          example = "root-partition";
          type = types.uniq (types.nullOr types.string);
          description = "Label of the device (if any).";
        };

        fsType = mkOption {
          default = "auto";
          example = "ext3";
          type = types.uniq types.string;
          description = "Type of the file system.";
        };

        options = mkOption {
          default = "defaults,relatime";
          example = "data=journal";
          type = types.string;
          merge = pkgs.lib.concatStringsSep ",";
          description = "Options used to mount the file system.";
        };

        autocreate = mkOption {
          default = false;
          type = types.bool;
          description = ''
            Automatically create the mount point defined in
            <option>fileSystems.*.mountPoint</option>.
          '';
        };

        noCheck = mkOption {
          default = false;
          type = types.bool;
          description = "Disable running fsck on this filesystem.";
        };
      };
    };

    system.fsPackages = mkOption {
      internal = true;
      default = [ ];
      description = "Packages supplying file system mounters and checkers.";
    };

    boot.supportedFilesystems = mkOption {
      default = [ ];
      example = [ "btrfs" ];
      type = types.list types.string;
      description = "Names of supported filesystem types.";
    };

    boot.initrd.supportedFilesystems = mkOption {
      default = [ ];
      example = [ "btrfs" ];
      type = types.list types.string;
      description = "Names of supported filesystem types in the initial ramdisk.";
    };

  };


  ###### implementation

  config = {

    boot.supportedFilesystems =
      map (fs: fs.fsType) config.fileSystems;

    boot.initrd.supportedFilesystems =
      map (fs: fs.fsType)
        (filter (fs: fs.mountPoint == "/" || fs.neededForBoot) config.fileSystems);

    # Add the mount helpers to the system path so that `mount' can find them.
    system.fsPackages = [ pkgs.dosfstools ];
    
    environment.systemPackages =
      [ pkgs.ntfs3g pkgs.cifs_utils pkgs.mountall ]
      ++ config.system.fsPackages;

    environment.etc = singleton
      { source = fstab;
        target = "fstab";
      };

    jobs.mountall =
      { startOn = "started udev";

        task = true;

        path = [ pkgs.utillinux pkgs.mountall ] ++ config.system.fsPackages;

        console = "output";

        preStart =
          ''
            # Ensure that this job is restarted when fstab changed:
            # ${fstab}
            
            ${optionalString config.services.nfs.client.enable ''
              ensure statd || true
            ''}

            echo "mounting filesystems..."
          '';

        daemonType = "daemon";
          
        exec = "mountall --daemon";
      };

    # The `mount-failed' event is emitted synchronously, but we don't
    # want `mountall' to wait for the emergency shell.  So use this
    # intermediate job to make the event asynchronous.
    jobs."mount-failed" =
      { task = true;
        startOn = "mount-failed";
        restartIfChanged = false;
        script =
          ''
            # Don't start the emergency shell if the X server is
            # running.  The user won't see it, and the "console owner"
            # stanza breaks VT switching and causes the X server to go
            # to 100% CPU time.
            status="$(status xserver || true)"
            [[ "$status" =~ start/ ]] && exit 0

            stop tty1 || true
            
            start --no-wait emergency-shell \
              DEVICE="$DEVICE" MOUNTPOINT="$MOUNTPOINT"
          '';
      };

    # On an `ip-up' event, notify mountall so that it retries mounting
    # remote filesystems.
    jobs."mountall-ip-up" =
      {
        task = true;
        startOn = "ip-up";
        restartIfChanged = false;
        script =
          ''
            # Send USR1 to the mountall process.  Can't use "pkill
            # mountall" here because that has a race condition: we may
            # accidentally send USR1 to children of mountall (such as
            # fsck) just before they do execve().
            status="$(status mountall)"
            if [[ "$status" =~ "start/running, process "([0-9]+) ]]; then
                pid=''${BASH_REMATCH[1]}
                echo "sending USR1 to $pid..."
                kill -USR1 "$pid"
            fi
          '';
      };

    jobs."emergency-shell" =
      { task = true;

        restartIfChanged = false;

        console = "owner";

        script =
          ''
            cat <<EOF

            [1;31m<<< Emergency shell >>>[0m

            The filesystem \`$DEVICE' could not be mounted on \`$MOUNTPOINT'.

            Please do one of the following:

            - Repair the filesystem (\`fsck $DEVICE') and exit the emergency
              shell to resume booting.

            - Ignore any failed filesystems and continue booting by running
              \`initctl emit filesystem'.

            - Remove the failed filesystem from the system configuration in
              /etc/nixos/configuration.nix and run \`nixos-rebuild switch'.

            EOF

            ${pkgs.shadow}/bin/login root || false

            initctl start --no-wait mountall
          '';
      };

  };

}
