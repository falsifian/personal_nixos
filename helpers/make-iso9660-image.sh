source $stdenv/setup

sources_=($sources)
targets_=($targets)

objects=($objects)
symlinks=($symlinks)

if test -n "$bootable"; then

    # The -boot-info-table option modifies the $bootImage file, so
    # find it in `contents' and make a copy of it (since the original
    # is read-only in the Nix store...).
    for ((i = 0; i < ${#targets_[@]}; i++)); do
        if test "${targets_[$i]}" = "$bootImage"; then
            echo "copying the boot image ${sources_[$i]}"
            cp "${sources_[$i]}" boot.img
            chmod u+w boot.img
            sources_[$i]=boot.img
        fi
    done

    bootFlags="-b $bootImage -c boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table"
fi

touch pathlist

# Add the individual files.
for ((i = 0; i < ${#targets_[@]}; i++)); do
    echo "${targets_[$i]}=$(readlink -f ${sources_[$i]})" >> pathlist
done


# Add the closures of the top-level store objects.
storePaths=$(perl $pathsFromGraph closure-*)
for i in $storePaths; do
    echo "${i:1}=$i" >> pathlist
done


# Also put a nix-pull manifest of the closures on the CD.
printManifest=1 perl $pathsFromGraph closure-* > MANIFEST
echo "MANIFEST=MANIFEST" >> pathlist


# Add symlinks to the top-level store objects.
for ((n = 0; n < ${#objects[*]}; n++)); do
    object=${objects[$n]}
    symlink=${symlinks[$n]}
    if test "$symlink" != "none"; then
        mkdir -p $(dirname ./$symlink)
        ln -s $object ./$symlink
        echo "$symlink=./$symlink" >> pathlist
    fi
done

cat pathlist

# !!! -f is a quick hack.
ensureDir $out/iso
genisoimage -r -J -o $out/iso/$isoName $bootFlags \
    -graft-points -path-list pathlist

ensureDir $out/nix-support
echo $system > $out/nix-support/system
