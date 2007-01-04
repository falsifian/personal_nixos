[


  { 
    name = ["networking" "hostName"];
    default = "nixos";
    description = "The name of the machine.";
  }

  
  {
    name = ["boot" "autoDetectRootDevice"];
    default = false;
    description = "
      Whether to find the root device automatically by searching for a
      device with the right label.  If this option is off, then a root
      file system must be specified using <option>fileSystems</option>.
    ";
  }


  {
    name = ["boot" "readOnlyRoot"];
    default = false;
    description = "
      Whether the root device should be mounted writable.  This should
      be set when booting from CD-ROM.
    ";
  }


  {
    name = ["boot" "rootLabel"];
    description = "
      When auto-detecting the root device (see
      <option>boot.autoDetectRootDevice</option>), this option
      specifies the label of the root device.  Right now, this is
      merely a file name that should exist in the root directory of
      the file system.  It is used to find the boot CD-ROM.
    ";
  }


  {
    name = ["boot" "grubDevice"];
    default = "";
    example = "/dev/hda";
    description = "
      The device on which the boot loader, Grub, will be installed.
      If empty, Grub won't be installed and it's your responsibility
      to make the system bootable.
    ";
  }


  {
    name = ["boot" "kernelParams"];
    default = [
      "selinux=0"
      "apm=on"
      "acpi=on"
      "vga=0x317"
      "console=tty1"
      "splash=verbose"
    ];
    description = "
      The kernel parameters.  If you want to add additional
      parameters, it's best to set
      <option>boot.extraKernelParams</options>.
    ";
  }


  {
    name = ["boot" "extraKernelParams"];
    default = [
    ];
    example = [
      "debugtrace"
    ];
    description = "
      Additional user-defined kernel parameters.
    ";
  }


  {
    name = ["boot" "hardwareScan"];
    default = true;
    description = "
      Whether to try to load kernel modules for all detected hardware.
      Usually this does a good job of providing you with the modules
      you need, but sometimes it can crash the system or cause other
      nasty effects.  If the hardware scan is turned on, it can be
      disabled at boot time by adding the <literal>safemode</literal>
      parameter to the kernel command line.
    ";
  }


  {
    name = ["boot" "kernelModules"];
    default = [];
    description = "
      The set of kernel modules to be loaded in the second stage of
      the boot process.  That is, these modules are not included in
      the initial ramdisk, so they'd better not be required for
      mounting the root file system.  Add them to
      <option>boot.initrd.extraKernelModules</options> if they are.
    ";
  }


  {
    name = ["boot" "initrd" "kernelModules"];
    default = [
      "ahci"
      "ata_piix"
      "sd_mod"
      "sr_mod"
      "ide-cd"
      "ide-disk"
      "ide-generic"
      "ext3"
    ];
    description = "
      The set of kernel modules in the initial ramdisk used during the
      boot process.  This set must include all modules necessary for
      mounting the root device.  That is, it should include modules
      for the physical device (e.g., SCSI drivers) and for the file
      system (e.g., ext3).  The set specified here is automatically
      closed under the module dependency relation, i.e., all
      dependencies of the modules list here are included
      automatically.  If you want to add additional
      modules, it's best to set
      <option>boot.initrd.extraKernelModules</options>.
    ";
  }


  {
    name = ["boot" "initrd" "extraKernelModules"];
    default = [];
    description = "
      Additional kernel modules for the initial ramdisk.  These are
      loaded before the modules listed in
      <option>boot.initrd.kernelModules</options>, so they take
      precedence.
    ";
  }


  {
    name = ["networking" "useDHCP"];
    default = true;
    description = "
      Whether to use DHCP to obtain an IP adress and other
      configuration for all network interfaces that are not manually
      configured.
    ";
  }

  
  {
    name = ["networking" "interfaces"];
    default = [];
    example = [
      { interface = "eth0";
        ipAddress = "131.211.84.78";
        netmask = "255.255.255.128";
        gateway = "131.211.84.1";
      }
    ];
    description = "
      The configuration for each network interface.  If
      <option>networking.useDHCP</option> is true, then each interface
      not listed here will be configured using DHCP.
    ";
  }

  
  {
    name = ["fileSystems"];
    default = [];
    example = [
      { mountPoint = "/";
        device = "/dev/hda1";
      }
      { mountPoint = "/data";
        device = "/dev/hda2";
        fsType = "ext3";
        options = "data=journal";
      }
    ];
    description = "
      The file systems to be mounted.  It must include an entry for
      the root directory (<literal>mountPoint = \"/\"</literal>) if
      <literal>boot.autoDetectRootDevice</literal> is not set.  Each
      entry in the list is an attribute set with the following fields:
      <literal>mountPoint</literal>, <literal>device</literal>,
      <literal>fsType</literal> (a file system type recognised by
      <command>mount</command>; defaults to
      <literal>\"auto\"</literal>), and <literal>options</literal>
      (the mount options passed to <command>mount</command> using the
      <option>-o</option> flag; defaults to <literal>\"defaults\"</literal>).
    ";
  }


  {
    name = ["swapDevices"];
    default = [];
    example = ["/dev/hda7" "/dev/hdb3" "/var/swapfile"];
    description = "
      The swap devices and swap files.  These must have been
      initialised using <command>mkswap</command>.
    ";
  }


  {
    name = ["services" "extraJobs"];
    default = [];
    description = "
      Additional Upstart jobs.
    ";
  }

  
  {
    name = ["services" "syslogd" "tty"];
    default = 10;
    description = "
      The tty device on which syslogd will print important log
      messages.
    ";
  }

      
  {
    name = ["services" "mingetty" "ttys"];
    default = [1 2 3 4 5 6];
    description = "
      The list of tty (virtual console) devices on which to start a
      login prompt.
    ";
  }

      
  {
    name = ["services" "mingetty" "waitOnMounts"];
    default = false;
    description = "
      Whether the login prompts on the virtual consoles will be
      started before or after all file systems have been mounted.  By
      default we don't wait, but if for example your /home is on a
      separate partition, you may want to turn this on.
    ";
  }

  
  {
    name = ["services" "sshd" "enable"];
    default = false;
    description = "
      Whether to enable the Secure Shell daemon, which allows secure
      remote logins.
    ";
  }

  
  {
    name = ["services" "sshd" "forwardX11"];
    default = false;
    description = "
      Whether to enable sshd to forward X11 connections.
    ";
  }

  
  {
    name = ["services" "ntp" "enable"];
    default = true;
    description = "
      Whether to synchronise your machine's time using the NTP
      protocol.
    ";
  }

  
  {
    name = ["services" "ntp" "servers"];
    default = [
      "0.pool.ntp.org"
      "1.pool.ntp.org"
      "2.pool.ntp.org"
    ];
    description = "
      The set of NTP servers from which to synchronise.
    ";
  }

  
  {
    name = ["services" "xserver" "enable"];
    default = false;
    description = "
      Whether to enable the X server.
    ";
  }

  
  {
    name = ["services" "httpd" "enable"];
    default = false;
    description = "
      Whether to enable the Apache httpd server.
    ";
  }

  
  {
    name = ["services" "httpd" "user"];
    default = "wwwrun";
    description = "
      User account under which httpd runs.  The account is created
      automatically if it doesn't exist.
    ";
  }

  
  {
    name = ["services" "httpd" "group"];
    default = "wwwrun";
    description = "
      Group under which httpd runs.  The account is created
      automatically if it doesn't exist.
    ";
  }

  
  {
    name = ["services" "httpd" "hostName"];
    default = "localhost";
    description = "
      Canonical hostname for the server.
    ";
  }

  
  {
    name = ["services" "httpd" "httpPort"];
    default = 80;
    description = "
      Port for unencrypted HTTP requests.
    ";
  }

  
  {
    name = ["services" "httpd" "httpsPort"];
    default = 443;
    description = "
      Port for encrypted HTTP requests.
    ";
  }

  
  {
    name = ["services" "httpd" "adminAddr"];
    example = "admin@example.org";
    description = "
      E-mail address of the server administrator.
    ";
  }

  
  {
    name = ["services" "httpd" "logDir"];
    default = "/var/log/httpd";
    description = "
      Directory for Apache's log files.  It is created automatically.
    ";
  }

  
  {
    name = ["services" "httpd" "stateDir"];
    default = "/var/run/httpd";
    description = "
      Directory for Apache's transient runtime state (such as PID
      files).  It is created automatically.  Note that the default,
      /var/run/httpd, is deleted at boot time.
    ";
  }

  
  {
    name = ["services" "httpd" "subservices" "subversion" "enable"];
    default = false;
    description = "
      Whether to enable the Subversion subservice in the webserver.
    ";
  }

  
  {
    name = ["services" "httpd" "subservices" "subversion" "notificationSender"];
    example = "svn-server@example.org";
    description = "
      The email address used in the Sender field of commit
      notification messages sent by the Subversion subservice.
    ";
  }

  
  {
    name = ["services" "httpd" "subservices" "subversion" "autoVersioning"];
    default = false;
    description = "
      Whether you want the Subversion subservice to support
      auto-versioning, which enables Subversion repositories to be
      mounted as read/writable file systems on operating systems that
      support WebDAV.
    ";
  }

  
]
