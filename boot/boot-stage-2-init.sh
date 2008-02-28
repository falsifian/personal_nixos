#! @shell@

# !!! copied from stage 1; remove duplication


# Print a greeting.
echo
echo "<<< NixOS Stage 2 >>>"
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


# Mount special file systems.
mkdir -m 0755 -p /etc
test -e /etc/fstab || touch /etc/fstab # to shut up mount
mkdir -m 0755 -p /proc
mount -n -t proc none /proc
cat /proc/mounts > /etc/mtab

mkdir -m 0755 -p /etc/nixos


# Process the kernel command line.
for o in $(cat /proc/cmdline); do
    case $o in
        debugtrace)
            # Show each command.
            set -x
            ;;
        debug2)
            echo "Debug shell called from @out@"
            exec @shell@
            ;;
        S|s|single)
            # !!! argh, can't pass a startup event to Upstart yet.
            exec @shell@
            ;;
        safemode)
            safeMode=1
            ;;
        systemConfig=*)
            set -- $(IFS==; echo $o)
            systemConfig=$2
            ;;
    esac
done


# More special file systems, initialise required directories.
mkdir -m 0755 -p /sys 
mount -t sysfs none /sys
mkdir -m 0755 -p /dev
mount -t tmpfs -o "mode=0755" none /dev
mkdir -m 0755 -p /dev/pts
mount -t devpts none /dev/pts
mount -t usbfs none /proc/bus/usb
mkdir -m 01777 -p /tmp 
mkdir -m 0755 -p /var
mkdir -m 0755 -p /nix/var
mkdir -m 0700 -p /root
mkdir -m 0755 -p /bin # for the /bin/sh symlink
mkdir -m 0755 -p /home


# Miscellaneous boot time cleanup.
rm -rf /var/run

if test -n "$safeMode"; then
    mkdir -m 0755 -p /var/run
    touch /var/run/safemode
fi


# Create the minimal device nodes needed before we run udev.
mknod -m 0666 /dev/null c 1 3
mknod -m 0644 /dev/urandom c 1 9 # needed for passwd


# Run the script that performs all configuration activation that does
# not have to be done at boot time.
@activateConfiguration@ "$systemConfig"


# Record the boot configuration.  !!! Should this be a GC root?
if test -n "$systemConfig"; then
    ln -sfn "$systemConfig" /var/run/booted-system
fi


# Ensure that the module tools can find the kernel modules.
export MODULE_DIR=@kernel@/lib/modules/


# Run any user-specified commands.
@shell@ @bootLocal@

resumeDevice="$(cat /proc/cmdline)"
resumeDevice="${resumeDevice##* resume=}"
resumeDevice="${resumeDevice%% *}"
echo "$resumeDevice"
if test -n "$resumeDevice"; then
    mkswap "$resumeDevice" || echo 'Failed to clear saved image.'
fi

# Start Upstart's init.  We start it through the
# /var/run/current-system symlink indirection so that we can upgrade
# init in a running system by changing the symlink and sending init a
# HUP signal.
export UPSTART_CFG_DIR=/etc/event.d
setPath "@upstartPath@"
exec /var/run/current-system/upstart/sbin/init
