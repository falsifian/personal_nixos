#! @shell@

# - [mount target device] <- currently disabled
# - make Nix store etc.
# - copy closure of Nix to target device
# - register validity
# - with a chroot to the target device:
#   * do a nix-pull
#   * nix-env -p /nix/var/nix/profiles/system -i <nix-expr for the configuration>
#   * run the activation script of the configuration (also installs Grub)

set -e

if test -z "$mountPoint"; then
    mountPoint=/mnt
fi

if test -z "$NIXOS"; then
    NIXOS=/etc/nixos/nixos
fi

if test -z "$NIXOS_CONFIG"; then
    NIXOS_CONFIG=/etc/nixos/configuration.nix
fi

if ! test -e "$mountPoint"; then
    echo "mount point $mountPoint doesn't exist"
    exit 1
fi

if ! grep -F -q " $mountPoint " /proc/mounts; then
    echo "$mountPoint doesn't appear to be a mount point"
    exit 1
fi
    
if ! test -e "$NIXOS"; then
    echo "NixOS source directory $NIXOS doesn't exist"
    exit 1
fi
    
if ! test -e "$NIXOS_CONFIG"; then
    echo "configuration file $NIXOS_CONFIG doesn't exist"
    exit 1
fi
    

NIXOS=$(readlink -f "$NIXOS")
NIXOS_CONFIG=$(readlink -f "$NIXOS_CONFIG")


# Mount some stuff in the target root directory.
mkdir -m 0755 -p $mountPoint/dev $mountPoint/proc $mountPoint/sys $mountPoint/mnt
mount --rbind / $mountPoint/mnt
mount --bind /dev $mountPoint/dev
mount --bind /proc $mountPoint/proc
mount --bind /sys $mountPoint/sys

cleanup() {
    # !!! don't umount any we didn't mount ourselves
    for i in $(grep -F "$mountPoint" /proc/mounts \
        | @perl@/bin/perl -e 'while (<>) { /^\S+\s+(\S+)\s+/; print "$1\n"; }' \
        | sort -r);
    do
        if test "$i" != "$mountPoint"; then
            umount $i
        fi
    done
}

trap "cleanup" EXIT

mkdir -m 01777 -p $mountPoint/tmp
mkdir -m 0755 -p $mountPoint/var


# Create the necessary Nix directories on the target device, if they
# don't already exist.
mkdir -m 0755 -p \
    $mountPoint/nix/var/nix/gcroots \
    $mountPoint/nix/var/nix/temproots \
    $mountPoint/nix/var/nix/manifests \
    $mountPoint/nix/var/nix/userpool \
    $mountPoint/nix/var/nix/profiles \
    $mountPoint/nix/var/nix/db \
    $mountPoint/nix/var/log/nix/drvs

mkdir -m 1777 -p \
    $mountPoint/nix/store \


# Get the store paths to copy from the references graph.
storePaths=$(@perl@/bin/perl @pathsFromGraph@ @nixClosure@)

# Copy Nix to the Nix store on the target device.
echo "copying Nix to $mountPoint...."
for i in $storePaths; do
    echo "  $i"
    rsync -a $i $mountPoint/nix/store/
done


# Register the paths in the Nix closure as valid.  This is necessary
# to prevent them from being deleted the first time we install
# something.  (I.e., Nix will see that, e.g., the glibc path is not
# valid, delete it to get it out of the way, but as a result nothing
# will work anymore.)
chroot $mountPoint @nix@/bin/nix-store --register-validity < @nixClosure@


# Create the required /bin/sh symlink; otherwise lots of things
# (notably the system() function) won't work.
mkdir -m 0755 -p $mountPoint/bin
# !!! assuming that @shell@ is in the closure
ln -sf @shell@ $mountPoint/bin/sh


# Enable networking in the chroot.
mkdir -m 0755 -p $mountPoint/etc
cp /etc/resolv.conf $mountPoint/etc/


# Pull the manifest on the CD so that everything in the Nix store on
# the CD can be copied directly.
echo "registering substitutes to speed up builds..."
rm -f $mountPoint/nix/var/nix/manifests/*
if test -e /MANIFEST; then
    chroot $mountPoint @nix@/bin/nix-pull file:///mnt/MANIFEST
fi
rm -f $mountPoint/tmp/inst-store
ln -s /mnt/nix/store $mountPoint/tmp/inst-store


# Do a nix-pull to speed up building.
if test -n "@nixpkgsURL@"; then
    chroot $mountPoint @nix@/bin/nix-pull @nixpkgsURL@/MANIFEST || true
fi


# Build the specified Nix expression in the target store and install
# it into the system configuration profile.
echo "building the system configuration..."
chroot $mountPoint @nix@/bin/nix-env \
    -p /nix/var/nix/profiles/system \
    -f "/mnt$NIXOS/system/system.nix" \
    --arg configuration "import /mnt$NIXOS_CONFIG" \
    --set -A system


# Copy the configuration to /etc/nixos.
backupTimestamp=$(date "+%Y%m%d%H%M%S")
targetConfig=$mountPoint/etc/nixos/configuration.nix
mkdir -p $(dirname $targetConfig)
if test -e $targetConfig -o -L $targetConfig; then
    cp -f $targetConfig $targetConfig.backup-$backupTimestamp
fi
if test "$NIXOS_CONFIG" != "$targetConfig"; then
    cp -f $NIXOS_CONFIG $targetConfig
fi


# Make a backup of the old NixOS/Nixpkgs sources.
echo "copying NixOS/Nixpkgs sources to /etc/nixos...."

targetNixos=$mountPoint/etc/nixos/nixos
if test -e $targetNixos; then
    mv $targetNixos $targetNixos.backup-$backupTimestamp
fi

targetNixpkgs=$mountPoint/etc/nixos/nixpkgs
if test -e $targetNixpkgs; then
    mv $targetNixpkgs $targetNixpkgs.backup-$backupTimestamp
fi


# Copy the NixOS/Nixpkgs sources to the target.
cp -prd $NIXOS $targetNixos
if test -e /etc/nixos/nixpkgs; then
    cp -prd /etc/nixos/nixpkgs $targetNixpkgs
fi
ln -sfn nixpkgs/pkgs/top-level/all-packages.nix $mountPoint/etc/nixos/install-source.nix


# Grub needs a mtab.
rootDevice=$(df $mountPoint | grep '^/' | sed 's^ .*^^')
echo "$rootDevice / somefs rw 0 0" > $mountPoint/etc/mtab


# Mark the target as a NixOS installation, otherwise
# switch-to-configuration will chicken out.
touch $mountPoint/etc/NIXOS


# Switch to the new system configuration.  This will install Grub with
# a menu default pointing at the kernel/initrd/etc of the new
# configuration.
echo "finalising the installation..."
NIXOS_INSTALL_GRUB=1 chroot $mountPoint \
    /nix/var/nix/profiles/system/bin/switch-to-configuration boot
