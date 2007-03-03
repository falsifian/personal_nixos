#! @shell@

export PATH="@path@"

exec > /var/log/udev-fw 2>&1

if test "$ACTION" = "add"; then

    ls -l /sys/$DEVPATH >> /tmp/fw 2>&1

    if ! test -e /sys/$DEVPATH/loading; then
        echo "Firmware loading is not supported by device \`DEVPATH'."
        exit 1
    fi

    for dir in @firmwareDirs@; do
        if test -e "$dir/$FIRMWARE"; then
            echo "Loading \`$FIRMWARE' for device \`$DEVPATH' from $dir."
            echo 1 > /sys/$DEVPATH/loading
            cat "$dir/$FIRMWARE" > /sys/$DEVPATH/data
            echo 0 > /sys/$DEVPATH/loading
            exit 0
        fi
    done

    echo "Firmware \`$FIRMWARE' for device \`$DEVPATH' not found."
    echo -1 > /sys/$DEVPATH/loading
    exit 1

fi
