#! @shell@ -e

# Allow the location of NixOS sources and the system configuration
# file to be overridden.

: ${mountPoint=/mnt}
: ${NIXOS_CONFIG=/etc/nixos/configuration.nix}

usage () {
  echo 1>&2 "
Usage: $0 [--install] [-v] [-d] [-l] [--xml] OPTION_NAME
       $0 [--install]

This program is used to explore NixOS options by looking at their values or
by looking at their description.  It is helpful for understanding how your
configuration is working.

Options:

  -i | --install        Use the configuration on
                        ${mountPoint:+$mountPoint/}$NIXOS_CONFIG instead of
                        the current system configuration.  Generate a
                        template configuration if no option name is
                        specified.
  -v | --value          Display the current value, based on your
                        configuration.
  -d | --description    Display the default value, the example and the
                        description.
  -l | --lookup         Display where the option is defined and where it
                        is declared.
  --xml                 Print an XML representation of the result.
                        Implies -vdl options.
  --help                Show this message.

Environment variables affecting $0:

  \$mountPoint          Path to the target file system.
  \$NIXOS_CONFIG        Path to your configuration file.

"

  exit 1;
}

#####################
# Process Arguments #
#####################

desc=false
defs=false
value=false
xml=false
install=false
verbose=false

option=""

argfun=""
for arg; do
  if test -z "$argfun"; then
    case $arg in
      -*)
        longarg=""
        sarg="$arg"
        while test "$sarg" != "-"; do
          case $sarg in
            --*) longarg=$arg; sarg="--";;
            -d*) longarg="$longarg --description";;
            -v*) longarg="$longarg --value";;
            -l*) longarg="$longarg --lookup";;
            -i*) longarg="$longarg --install";;
            -*) usage;;
          esac
          # remove the first letter option
          sarg="-${sarg#??}"
        done
        ;;
      *) longarg=$arg;;
    esac
    for larg in $longarg; do
      case $larg in
        --description) desc=true;;
        --value) value=true;;
        --lookup) defs=true;;
        --xml) xml=true;;
        --install) install=true;;
        --verbose) verbose=true;;
        --help) usage;;
        -*) usage;;
        *) if test -z "$option"; then
             option="$larg"
           else
             usage
           fi;;
      esac
    done
  else
    case $argfun in
      set_*)
        var=$(echo $argfun | sed 's,^set_,,')
        eval $var=$arg
        ;;
    esac
    argfun=""
  fi
done

if $xml; then
  value=true
  desc=true
  defs=true
fi

# --install cannot be used with -d -v -l without option name.
if $value || $desc || $defs && $install && test -z "$option"; then
  usage
fi

generate=false
if ! $defs && ! $desc && ! $value && $install && test -z "$option"; then
  generate=true
fi

if ! $defs && ! $desc; then
  value=true
fi

if $verbose; then
  set -x
else
  set +x
fi

#############################
# Process the configuration #
#############################

evalNix(){
  nix-instantiate - --eval-only "$@"
}

evalAttr(){
  local prefix=$1
  local suffix=$2
  local strict=$3
  echo "(import $NIXOS {}).$prefix${option:+.$option}${suffix:+.$suffix}" |
    evalNix ${strict:+--strict}
}

evalOpt(){
  evalAttr "eval.options" "$@"
}

evalCfg(){
  evalAttr "config" "$@"
}

findSources(){
  local suffix=$1
  echo "builtins.map (f: f.source) (import $NIXOS {}).eval.options${option:+.$option}.$suffix" |
    evalNix --strict
}

# Given a result from nix-instantiate, recover the list of attributes it
# contains.
attrNames() {
  local attributeset=$1
  # sed is used to replace un-printable subset by 0s, and to remove most of
  # the inner-attribute set, which reduce the likelyhood to encounter badly
  # pre-processed input.
  echo "builtins.attrNames $attributeset" | \
    sed 's,<[A-Z]*>,0,g; :inner; s/{[^\{\}]*};/0;/g; t inner;' | \
    evalNix --strict
}

# map a simple list which contains strings or paths.
nixMap() {
  local fun="$1"
  local list="$2"
  local elem
  for elem in $list; do
    test $elem = '[' -o $elem = ']' && continue;
    $fun $elem
  done
}

if $install; then
  export NIXOS_CONFIG="$mountPoint$NIXOS_CONFIG"
fi

if $generate; then
  mkdir -p $(dirname "$NIXOS_CONFIG")

  # Scan the hardware and add the result to /etc/nixos/hardware-scan.nix.
  hardware_config="${NIXOS_CONFIG%/configuration.nix}/hardware-configuration.nix"
  if test -e "$hardware_config"; then
    echo "A hardware configuration file exists, generation skipped."
  else
    echo "Scan your hardware to generate a hardware configuration file."
    nixos-hardware-scan > "$hardware_config"
  fi

  if test -e "$NIXOS_CONFIG"; then
    echo 1>&2 "error: Cannot generate a template configuration because a configuration file exists."
    exit 1
  fi

  echo "Generate a template configuration that you should edit."

  # Generate a template configuration file where the user has to
  # fill the gaps.
  echo > "$NIXOS_CONFIG" \
'# Edit this configuration file which defines what would be installed on the
# system.  To Help while choosing option value, you can watch at the manual
# page of configuration.nix or at the last chapter of the manual available
# on the virtual console 8 (Alt+F8).

{config, pkgs, ...}:

{
  require = [
    # Include the configuration for part of your system which have been
    # detected automatically.
    ./hardware-configuration.nix
  ];

  boot.initrd.kernelModules = [
    # Specify all kernel modules that are necessary for mounting the root
    # file system.
    #
    # "ext4" "ata_piix"
  ];

  boot.loader.grub = {
    # Use grub 2 as boot loader.
    enable = true;
    version = 2;

    # Define on which hard drive you want to install Grub.
    # device = "/dev/sda";
  };

  networking = {
    # hostName = "nixos"; # Define your hostname.
    interfaceMonitor.enable = true; # Watch for plugged cable.
    enableWLAN = true;  # Enables Wireless.
  };

  # Add file system entries for each partition that you want to see mounted
  # at boot time.  You can add filesystems which are not mounted at boot by
  # adding the noauto option.
  fileSystems = [
    # Mount the root file system
    #
    # { mountPoint = "/";
    #   device = "/dev/sda2";
    # }

    # Copy & Paste & Uncomment & Modify to add any other file system.
    #
    # { mountPoint = "/data"; # where you want to mount the device
    #   device = "/dev/sdb"; # the device or the label of the device
    #   # label = "data";
    #   fsType = "ext3";      # the type of the partition.
    #   options = "data=journal";
    # }
  ];

  swapDevices = [
    # List swap partitions that are mounted at boot time.
    #
    # { device = "/dev/sda1"; }
  ];

  # Select internationalisation properties.
  # i18n = {
  #   consoleFont = "lat9w-16";
  #   consoleKeyMap = "us";
  #   defaultLocale = "en_US.UTF-8";
  # };

  # List services that you want to enable:

  # Add an OpenSSH daemon.
  # services.openssh.enable = true;

  # Add CUPS to print documents.
  # services.printing.enable = true;

  # Add XServer (default if you have used a graphical iso)
  # services.xserver = {
  #   enable = true;
  #   layout = "us";
  #   xkbOptions = "eurosign:e";
  # };

  # Add the NixOS Manual on virtual console 8
  services.nixosManual.showManual = true;
}
'

  exit 0
fi;

# This dupplicate the work made below, but it is useful for processing the
# output of nixos-option with other tools such as nixos-gui.
if $xml; then
  evalNix --xml --no-location <<EOF
let
  reach = attrs: attrs${option:+.$option};
  nixos = <nixos>;
  nixpkgs = <nixpkgs>;
  sources = builtins.map (f: f.source);
  opt = reach nixos.eval.options;
  cfg = reach nixos.config;
in

with nixpkgs.lib;

let
  optStrict = v:
    let
      traverse = x :
        if isAttrs x then
          if x ? outPath then true
          else all id (mapAttrsFlatten (n: traverseNoAttrs) x)
        else traverseNoAttrs x;
      traverseNoAttrs = x:
        # do not continue in attribute sets
        if isAttrs x then true
        else if isList x then all id (map traverse x)
        else true;
    in assert traverse v; v;
in

if isOption opt then
  optStrict ({}
  // optionalAttrs (opt ? default) { inherit (opt) default; }
  // optionalAttrs (opt ? example) { inherit (opt) example; }
  // optionalAttrs (opt ? description) { inherit (opt) description; }
  // optionalAttrs (opt ? type) { typename = opt.type.name; }
  // optionalAttrs (opt ? options) { inherit (opt) options; }
  // {
    # to disambiguate the xml output.
    _isOption = true;
    declarations = sources opt.declarations;
    definitions = sources opt.definitions;
    value = cfg;
  })
else
  opt
EOF
  exit $?
fi

if test "$(evalOpt "_type" 2> /dev/null)" = '"option"'; then
  $value && evalCfg;

  if $desc; then
    $value && echo;

    if default=$(evalOpt "default" - 2> /dev/null); then
      echo "Default: $default"
    else
      echo "Default: <None>"
    fi
    if example=$(evalOpt "example" - 2> /dev/null); then
      echo "Example: $example"
    fi
    echo "Description:"
    eval printf $(evalOpt "description")
  fi

  if $defs; then
    $desc || $value && echo;

    printPath () { echo "  $1"; }

    echo "Declared by:"
    nixMap printPath "$(findSources "declarations")"
    echo ""
    echo "Defined by:"
    nixMap printPath "$(findSources "definitions")"
    echo ""
  fi

else
  # echo 1>&2 "Warning: This value is not an option."

  result=$(evalCfg)
  if names=$(attrNames "$result" 2> /dev/null); then
    echo 1>&2 "This attribute set contains:"
    escapeQuotes () { eval echo "$1"; }
    nixMap escapeQuotes "$names"
  else
    echo 1>&2 "An error occured while looking for attribute names."
    echo $result
  fi
fi
