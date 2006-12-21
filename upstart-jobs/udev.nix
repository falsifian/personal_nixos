{writeText, cleanSource, udev, procps}:

let

  conf = writeText "udev.conf" "
    udev_rules=\"${cleanSource ./udev-rules}\"
  ";

in

{
  name = "udev";
  
  job = "
start on startup
stop on shutdown

env UDEV_CONFIG_FILE=${conf}

start script
    echo '' > /proc/sys/kernel/hotplug

    # Get rid of possible old udev processes.
    ${procps}/bin/pkill -u root '^udevd$' || true

    # Start udev.
    ${udev}/sbin/udevd --daemon

    # Let udev create device nodes for all modules that have already
    # been loaded into the kernel (or for which support is built into
    # the kernel).
    ${udev}/sbin/udevtrigger
    ${udev}/sbin/udevsettle # wait for udev to finish

    # Kill udev, let Upstart restart and monitor it.  (This is nasty,
    # but we have to run udevtrigger first.  Maybe we can use
    # Upstart's `binary' keyword, but it isn't implemented yet.)
    if ! ${procps}/bin/pkill -u root '^udevd$'; then
        echo \"couldn't stop udevd\"
    fi

    while ${procps}/bin/pgrep -u root '^udevd$'; do
        sleep 1
    done

    initctl emit new-devices
end script

respawn ${udev}/sbin/udevd
  ";

}
