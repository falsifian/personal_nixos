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

if test -z "$NIXOS_CONFIG"; then
    NIXOS_CONFIG=/mnt/etc/nixos/configuration.nix
fi

if ! test -e "$mountPoint"; then
    echo "mount point $mountPoint doesn't exist"
    exit 1
fi

if ! grep -F -q " $mountPoint " /proc/mounts; then
    echo "$mountPoint doesn't appear to be a mount point"
    exit 1
fi
    
if ! test -e "$NIXOS_CONFIG"; then
    echo "configuration file $NIXOS_CONFIG doesn't exist"
    exit 1
fi
    

# Enable networking in the chroot.
mkdir -m 0755 -p $mountPoint/etc
touch /etc/resolv.conf 
cp -f /etc/resolv.conf $mountPoint/etc/
rm -f $mountPoint/etc/hosts
cat /etc/hosts > $mountPoint/etc/hosts
rm -f $mountPoint/etc/nsswitch.conf
cat /etc/nsswitch.conf > $mountPoint/etc/nsswitch.conf

# Mount some stuff in the target root directory.
mkdir -m 0755 -p $mountPoint/dev $mountPoint/proc $mountPoint/sys $mountPoint/mnt
mount --rbind /dev $mountPoint/dev
mount --rbind /proc $mountPoint/proc
mount --rbind /sys $mountPoint/sys
mount --rbind / $mountPoint/mnt

cleanup() {
    umount -l $mountPoint/mnt
    umount -l $mountPoint/dev
    umount -l $mountPoint/proc
    umount -l $mountPoint/sys
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


# We don't have locale-archive in the chroot, so clear $LANG.
export LANG=
export LC_ALL=
export LC_TIME=


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


# Make the build below copy paths from the CD if possible.  Note that
# /mnt in the chroot is the root of the CD.
export NIX_OTHER_STORES=/mnt/nix:$NIX_OTHER_STORES


# Do a nix-pull to speed up building.
if test -n "@nixpkgsURL@" -a ${NIXOS_PULL:-1} != 0; then
    chroot $mountPoint @nix@/bin/nix-pull @nixpkgsURL@/MANIFEST || true
fi

if test -n "$NIXOS_PREPARE_CHROOT_ONLY"; then
    echo "User requested only to prepare chroot. Exiting."
    exit 0;
fi

# Build the specified Nix expression in the target store and install
# it into the system configuration profile.
echo "building the system configuration..."
NIX_PATH=nixpkgs=/mnt/etc/nixos/nixpkgs:nixos=/mnt/etc/nixos/nixos:nixos-config="/mnt$NIXOS_CONFIG" NIXOS_CONFIG= \
    chroot $mountPoint @nix@/bin/nix-env \
    -p /nix/var/nix/profiles/system -f '<nixos>' --set -A system --show-trace


# Make a backup of the old NixOS/Nixpkgs sources.
echo "copying NixOS/Nixpkgs sources to /etc/nixos...."

backupTimestamp=$(date "+%Y%m%d%H%M%S")

targetNixos=$mountPoint/etc/nixos/nixos
if test -e $targetNixos; then
    mv $targetNixos $targetNixos.backup-$backupTimestamp
fi

targetNixpkgs=$mountPoint/etc/nixos/nixpkgs
if test -e $targetNixpkgs; then
    mv $targetNixpkgs $targetNixpkgs.backup-$backupTimestamp
fi


# Copy the NixOS/Nixpkgs sources to the target.
cp -prd /etc/nixos/nixos $targetNixos
if [ -e /etc/nixos/nixpkgs ]; then
    cp -prd /etc/nixos/nixpkgs $targetNixpkgs
fi


# Grub needs an mtab.
ln -sfn /proc/mounts $mountPoint/etc/mtab


# Mark the target as a NixOS installation, otherwise
# switch-to-configuration will chicken out.
touch $mountPoint/etc/NIXOS


# Switch to the new system configuration.  This will install Grub with
# a menu default pointing at the kernel/initrd/etc of the new
# configuration.
echo "finalising the installation..."
NIXOS_INSTALL_GRUB=1 chroot $mountPoint \
    /nix/var/nix/profiles/system/bin/switch-to-configuration boot
