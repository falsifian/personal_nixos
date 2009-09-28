{pkgs, config, ...}:

with pkgs.lib;

let

  inherit (pkgs) stdenv writeText udev procps;

  cfg = config.services.udev;

  extraUdevRules = pkgs.writeTextFile {
    name = "extra-udev-rules";
    text = cfg.extraRules;
    destination = "/etc/udev/rules.d/10-local.rules";
  };

  modprobe = config.system.sbin.modprobe;
    
  nixosRules = ''
  
    # Miscellaneous devices.
    KERNEL=="sonypi",               MODE="0666"
    KERNEL=="kvm",                  MODE="0666"
    KERNEL=="kqemu",                NAME="%k", MODE="0666"
    KERNEL=="vboxdrv", NAME="vboxdrv", OWNER="root", GROUP="root", MODE="0666"

  '';
  
  # Perform substitutions in all udev rules files.
  udevRules = stdenv.mkDerivation {
    name = "udev-rules";
    buildCommand = ''
      ensureDir $out
      shopt -s nullglob

      # Use all the default udev rules.
      cp ${udev}/libexec/rules.d/*.rules $out/

      # Set a reasonable $PATH for programs called by udev rules.
      echo 'ENV{PATH}="${pkgs.coreutils}/bin:${pkgs.gnused}/bin:${pkgs.utillinux}/bin"' > $out/00-path.rules

      # Set the firmware search path so that the firmware.sh helper
      # called by 50-firmware.rules works properly.
      echo 'ENV{FIRMWARE_DIRS}="${toString config.hardware.firmware}"' >> $out/00-path.rules
      
      # Fix some paths in the standard udev rules.
      for i in $out/*.rules; do
        substituteInPlace $i \
          --replace /sbin/modprobe ${modprobe}/sbin/modprobe \
          --replace /sbin/blkid ${pkgs.utillinux}/sbin/blkid \
          --replace /sbin/mdadm ${pkgs.mdadm}/sbin/madm
      done

      # If auto-configuration is disabled, then remove
      # udev's 80-drivers.rules file, which contains rules for
      # automatically calling modprobe.
      ${if !config.boot.hardwareScan then "rm $out/80-drivers.rules" else ""}

      # Add the udev rules from other packages.
      for i in ${toString cfg.packages}; do
        for j in $i/*/udev/rules.d/*; do
          ln -s $j $out/$(basename $j)
        done
      done

      # Use the persistent device rules (naming for CD/DVD and
      # network devices) stored in 
      # /var/lib/udev/rules.d/70-persistent-{cd,net}.rules.  These are
      # modified by the write_{cd,net}_rules helpers called from
      # 75-cd-aliases-generator.rules and
      # 75-persistent-net-generator.rules.
      ln -s /var/lib/udev/rules.d/70-persistent-cd.rules $out/
      ln -s /var/lib/udev/rules.d/70-persistent-net.rules $out/
    ''; # */
  };

  # The udev configuration file.
  conf = writeText "udev.conf" ''
    udev_rules="${udevRules}"
    #udev_log="debug"
  '';

in

{

  ###### interface
  
  options = {

    boot.hardwareScan = mkOption {
      default = true;
      description = ''
        Whether to try to load kernel modules for all detected hardware.
        Usually this does a good job of providing you with the modules
        you need, but sometimes it can crash the system or cause other
        nasty effects.  If the hardware scan is turned on, it can be
        disabled at boot time by adding the <literal>safemode</literal>
        parameter to the kernel command line.
      '';
    };
  
    services.udev = {

      packages = mkOption {
        default = [];
        merge = mergeListOption;
        description = ''
          List of packages containing <command>udev</command> rules.
          All files found in
          <filename><replaceable>pkg</replaceable>/etc/udev/rules.d</filename> and
          <filename><replaceable>pkg</replaceable>/lib/udev/rules.d</filename>
          will be included.
        '';
      };

      extraRules = mkOption {
        default = "";
        example = ''
          KERNEL=="eth*", ATTR{address}=="00:1D:60:B9:6D:4F", NAME="my_fast_network_card"
        '';
        merge = mergeStringOption;
        description = ''
          Additional <command>udev</command> rules. They'll be written
          into file <filename>10-local.rules</filename>. Thus they are
          read before all other rules.
        '';
      };

    };
    
    hardware.firmware = mkOption {
      default = [];
      example = ["/root/my-firmware"];
      merge = mergeListOption; 
      description = ''
        List of directories containing firmware files.  Such files
        will be loaded automatically if the kernel asks for them
        (i.e., when it has detected specific hardware that requires
        firmware to function).
      '';
    };
    
  };
  

  ###### implementation

  config = {

    services.udev.extraRules = nixosRules;
    
    services.udev.packages = [extraUdevRules];

    jobs = singleton
      { name = "udev";

        startOn = "startup";
        stopOn = "shutdown";

        environment = { UDEV_CONFIG_FILE = conf; };

        preStart =
          ''
            echo "" > /proc/sys/kernel/hotplug

            mkdir -p /var/lib/udev/rules.d

            # Get rid of possible old udev processes.
            ${procps}/bin/pkill -u root "^udevd$" || true

            # Do the loading of additional stage 2 kernel modules.
            # Maybe this isn't the best place...
            for i in ${toString config.boot.kernelModules}; do
                echo "Loading kernel module $i..."
                ${modprobe}/sbin/modprobe $i || true
            done

            # Start udev.
            mkdir -p /dev/.udev # !!! bug in udev?
            ${udev}/sbin/udevd --daemon

            # Let udev create device nodes for all modules that have already
            # been loaded into the kernel (or for which support is built into
            # the kernel).
            ${udev}/sbin/udevadm trigger
            ${udev}/sbin/udevadm settle # wait for udev to finish

            # Kill udev, let Upstart restart and monitor it.  (This is nasty,
            # but we have to run `udevadm trigger' first.  Maybe we can use
            # Upstart's `binary' keyword, but it isn't implemented yet.)
            if ! ${procps}/bin/pkill -u root "^udevd$"; then
                echo "couldn't stop udevd"
            fi

            while ${procps}/bin/pgrep -u root "^udevd$"; do
                sleep 1
            done

            initctl emit new-devices
          '';

        exec = "${udev}/sbin/udevd";

      };

  };

}
