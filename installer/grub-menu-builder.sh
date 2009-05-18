#! @bash@/bin/sh -e

shopt -s nullglob

export PATH=/empty
for i in @path@; do PATH=$PATH:$i/bin; done

default=$1
if test -z "$1"; then
    echo "Syntax: grub-menu-builder.sh <DEFAULT-CONFIG>"
    exit 1
fi

bootMount="@bootMount@"
if test -z "$bootMount"; then bootMount=/boot; fi


echo "updating the Grub menu..."


target=/boot/grub/menu.lst
tmp=$target.tmp

cat > $tmp << GRUBEND
# Automatically generated.  DO NOT EDIT THIS FILE!
default 0
timeout 5
GRUBEND


if test -n "@grubSplashImage@"; then
    splashLocation=@grubSplashImage@
    # Splash images in /nix/store don't seem to work, so copy them.
    cp -f $splashLocation /boot/background.xpm.gz
    splashLocation="$bootMount/background.xpm.gz"
    echo "splashimage $splashLocation" >> $tmp
fi


configurationCounter=0
configurationLimit="@configurationLimit@"
numAlienEntries=`cat <<EOF | egrep '^[[:space:]]*title' | wc -l
@extraGrubEntries@
EOF`

if test $((configurationLimit+numAlienEntries)) -gt 190; then
    configurationLimit=$((190-numAlienEntries));
fi


# Convert a path to a file in the Nix store such as
# /nix/store/<hash>-<name>/file to <hash>-<name>-<file>.
cleanName() {
    local path="$1"
    echo "$path" | sed 's|^/nix/store/||' | sed 's|/|-|g'
}


# Copy a file from the Nix store to /boot/kernels.
declare -A filesCopied

copyToKernelsDir() {
    local src="$1"
    local dst="/boot/kernels/$(cleanName $src)"
    # Don't copy the file if $dst already exists.  This means that we
    # have to create $dst atomically to prevent partially copied
    # kernels or initrd if this script is ever interrupted.
    if ! test -e $dst; then
        local dstTmp=$dst.tmp.$$
        cp $src $dstTmp
        mv $dstTmp $dst
    fi
    filesCopied[$dst]=1
    result=$dst
}


# Add an entry for a configuration to the Grub menu, and if
# appropriate, copy its kernel and initrd to /boot/kernels.
addEntry() {
    local name="$1"
    local path="$2"
    local shortSuffix="$3"

    configurationCounter=$((configurationCounter + 1))
    if test $configurationCounter -gt @configurationLimit@; then
	return
    fi

    if ! test -e $path/kernel -a -e $path/initrd; then
        return
    fi

    local kernel=$(readlink -f $path/kernel)
    local initrd=$(readlink -f $path/initrd)

    if test "$path" = "$default"; then
	cp "$kernel" /boot/nixos-kernel
	cp "$initrd" /boot/nixos-initrd
	cp "$(readlink -f "$path/init")" /boot/nixos-init
	cat > /boot/nixos-grub-config <<EOF
	title Emergency boot
	kernel ${bootMount:-/boot}/nixos-kernel systemConfig=$(readlink -f "$path") init=/boot/nixos-init $(cat "$path/kernel-params")
	initrd ${bootMount:-/boot}/nixos-initrd
EOF
    fi

    if test -n "@copyKernels@"; then
        copyToKernelsDir $kernel; kernel=$result
        copyToKernelsDir $initrd; initrd=$result
    fi
    
    if test -n "$bootMount"; then
        kernel=$(echo $kernel | sed -e "s^/boot^$bootMount^")
        initrd=$(echo $initrd | sed -e "s^/boot^$bootMount^")
    fi
    
    local confName=$(if test -e $path/configuration-name; then 
	cat $path/configuration-name; 
    fi)
    if test -n "$confName"; then
	name="$confName $3"
    fi

    cat >> $tmp << GRUBEND

title $name
  kernel $kernel systemConfig=$(readlink -f $path) init=$(readlink -f $path/init) $(cat $path/kernel-params)
  initrd $initrd
GRUBEND
}


if test -n "@copyKernels@"; then
    mkdir -p /boot/kernels
fi


# Additional entries specified verbatim by the configuration.
extraGrubEntries=`cat <<EOF
@extraGrubEntries@
EOF`


if test -n "@extraGrubEntriesBeforeNixos@"; then 
    echo "$extraGrubEntries" >> $tmp
fi

addEntry "NixOS - Default" $default ""

if test -z "@extraGrubEntriesBeforeNixos@"; then 
    echo "$extraGrubEntries" >> $tmp
fi

# Add all generations of the system profile to the menu, in reverse
# (most recent to least recent) order.
for link in $((ls -d $default/fine-tune/* ) | sort -n); do
    date=$(stat --printf="%y\n" $link | sed 's/\..*//')
    addEntry "NixOS - variation" $link ""
done

for generation in $(
    (cd /nix/var/nix/profiles && ls -d system-*-link) \
    | sed 's/system-\([0-9]\+\)-link/\1/' \
    | sort -n -r); do
    link=/nix/var/nix/profiles/system-$generation-link
    date=$(stat --printf="%y\n" $link | sed 's/\..*//')
    kernelVersion=$(cd $(dirname $(readlink -f $link/kernel))/lib/modules && echo *)
    addEntry "NixOS - Configuration $generation ($date - $kernelVersion)" $link "$generation ($date)"
done


# Atomically update /boot/grub/menu.lst.  !!! should do an fsync()
# here on $tmp, especially on ext4.
mv $tmp $target


# Remove obsolete files from /boot/kernels.
for fn in $(ls /boot/kernels/*); do
    if ! test "${filesCopied[$fn]}" = 1; then
        rm -vf -- "$fn"
    fi
done
