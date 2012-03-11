#! @shell@

systemConfig=@systemConfig@


# Print a greeting.
echo
echo -e "\e[1;32m<<< NixOS Stage 2 >>>\e[0m"
echo


# Set the PATH.
setPath() {
    local dirs="$1"
    export PATH=/empty
    for i in $dirs; do
        PATH=$PATH:$i/bin
        if test -e $i/sbin; then
            PATH=$PATH:$i/sbin
        fi
    done
}

setPath "@path@"


# Normally, stage 1 mounts the root filesystem read/writable.
# However, in some environments (such as Amazon EC2), stage 2 is
# executed directly, and the root is read-only.  So make it writable
# here.
mount -n -o remount,rw none /


# Likewise, stage 1 mounts /proc, /dev and /sys, so if we don't have a
# stage 1, we need to do that here.
if [ ! -e /proc/1 ]; then
    mkdir -m 0755 -p /proc
    mount -n -t proc none /proc
    mkdir -m 0755 -p /sys
    mount -t sysfs none /sys
    mkdir -m 0755 -p /dev
    mount -t tmpfs -o "mode=0755" none /dev

    # Create the minimal device nodes needed for the activation scripts
    # and Upstart.
    mknod -m 0666 /dev/null c 1 3
    mknod -m 0644 /dev/urandom c 1 9 # needed for passwd
    mknod -m 0644 /dev/console c 5 1
    mknod -m 0644 /dev/tty1 c 4 1
    mknod -m 0644 /dev/ttyS0 c 4 64
    mknod -m 0644 /dev/ttyS1 c 4 65
fi


# Provide a /etc/mtab.
mkdir -m 0755 -p /etc
test -e /etc/fstab || touch /etc/fstab # to shut up mount
rm -f /etc/mtab* # not that we care about stale locks
cat /proc/mounts > /etc/mtab


# Process the kernel command line.
debug2=
for o in $(cat /proc/cmdline); do
    case $o in
        debugtrace)
            # Show each command.
            set -x
            ;;
        debug2)
            debug2=1
            ;;
        S|s|single)
            # !!! argh, can't pass a startup event to Upstart yet.
            exec @shell@
            ;;
        resume=*)
            set -- $(IFS==; echo $o)
            resumeDevice=$2
            ;;
    esac
done


# More special file systems, initialise required directories.
mkdir -m 0777 /dev/shm
mount -t tmpfs -o "rw,nosuid,nodev,size=@devShmSize@" tmpfs /dev/shm
mkdir -m 0755 -p /dev/pts
mount -t devpts -o mode=0600,gid=@ttyGid@ none /dev/pts
[ -e /proc/bus/usb ] && mount -t usbfs none /proc/bus/usb # UML doesn't have USB by default
mkdir -m 01777 -p /tmp
mkdir -m 0755 -p /var
mkdir -m 0755 -p /nix/var
mkdir -m 0700 -p /root
mkdir -m 0755 -p /bin # for the /bin/sh symlink
mkdir -m 0755 -p /home
mkdir -m 0755 -p /etc/nixos


# Miscellaneous boot time cleanup.
rm -rf /var/run /var/lock /var/log/upstart
rm -f /etc/resolv.conf

#echo -n "cleaning \`/tmp'..."
#rm -rf --one-file-system /tmp/*
#echo " done"


# Get rid of ICE locks and ensure that it's owned by root.
rm -rf /tmp/.ICE-unix
mkdir -m 1777 /tmp/.ICE-unix


# This is a good time to clean up /nix/var/nix/chroots.  Doing an `rm
# -rf' on it isn't safe in general because it can contain bind mounts
# to /nix/store and other places.  But after rebooting these are all
# gone, of course.
rm -rf /nix/var/nix/chroots # recreated in activate-configuration.sh


# Also get rid of temporary GC roots.
rm -rf /nix/var/nix/gcroots/tmp /nix/var/nix/temproots


# Create a tmpfs on /run to hold runtime state for programs such as
# udev (if stage 1 hasn't already done so).
if ! mountpoint -q /run; then
    rm -rf /run
    mkdir -m 0755 -p /run
    mount -t tmpfs -o "mode=0755,size=@runSize@" none /run
fi

mkdir -m 0700 -p /run/lock


# For backwards compatibility, symlink /var/run to /run, and /var/lock
# to /run/lock.
ln -s /run /var/run
ln -s /run/lock /var/lock


# Clear the resume device.
if test -n "$resumeDevice"; then
    mkswap "$resumeDevice" || echo 'Failed to clear saved image.'
fi


# Run the script that performs all configuration activation that does
# not have to be done at boot time.
echo "running activation script..."
$systemConfig/activate


# Record the boot configuration.
ln -sfn "$systemConfig" /var/run/booted-system

# Prevent the booted system form being garbage-collected If it weren't
# a gcroot, if we were running a different kernel, switched system,
# and garbage collected all, we could not load kernel modules anymore.
ln -sfn /var/run/booted-system /nix/var/nix/gcroots/booted-system


# Ensure that the module tools can find the kernel modules.
export MODULE_DIR=@kernel@/lib/modules/


# Run any user-specified commands.
@shell@ @postBootCommands@


# For debugging Upstart.
if [ -n "$debug2" ]; then
    # Get the console from the kernel cmdline
    console=tty1
    for o in $(cat /proc/cmdline); do
      case $o in
        console=*)
          set -- $(IFS==; echo $o)
          console=$2
          ;;
      esac
    done

    echo "Debug shell called from @out@"
    setsid @shell@ < /dev/$console >/dev/$console 2>/dev/$console
fi


# Start Upstart's init.
echo "starting Upstart..."
PATH=/var/run/current-system/upstart/sbin exec init ${debug2:+--verbose}
