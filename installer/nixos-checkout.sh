#! @shell@ -e
set -x

# Pull the manifests defined in the configuration (the "manifests"
# attribute).  Wonderfully hacky *and* cut&pasted from nixos-installer.sh!!!
if test -z "$NIXOS"; then NIXOS=/etc/nixos/nixos; fi
if test -z "$NIXOS_NO_PULL"; then
    manifests=$(nix-instantiate --eval-only --xml --strict $NIXOS -A manifests \
        | grep '<string'  | sed 's^.*"\(.*\)".*^\1^g')

    mkdir -p /nix/var/nix/channel-cache
    for i in $manifests; do
        NIX_DOWNLOAD_CACHE=/nix/var/nix/channel-cache nix-pull $i || true
    done
fi

# Obtain Subversion.
if test -z "$(type -tp svn)"; then
    #nix-channel --add http://nix.cs.uu.nl/dist/nix/channels-v3/nixpkgs-unstable
    #nix-channel --update
    nix-env -i subversion
fi

cd /etc/nixos

if test -n "$NIXOS" && test "$NIXOS_BRANCH" = 1 && test -z "$CHECKOUT_BRANCH" && ! test "$NIXOS" = "/etc/nixos/nixos"; then
	CHECKOUT_BRANCH=${NIXOS##*/}
	CHECKOUT_BRANCH=${CHECKOUT_BRANCH#nixos-}
	CHECKOUT_BRANCH=branches/${CHECKOUT_BRANCH}
	CHECKOUT_SUFFIX=-${CHECKOUT_BRANCH##*/}
fi

if test -n "${CHECKOUT_BRANCH}" && test -z "${CHECKOUT_SUFFIX}" ; then
	CHECKOUT_SUFFIX=-${CHECKOUT_BRANCH##*/}
fi;

# Move any old nixos or nixpkgs directories out of the way.
backupTimestamp=$(date "+%Y%m%d%H%M%S")

if test -e nixos -a ! -e nixos/.svn; then
    mv nixos${CHECKOUT_SUFFIX} nixos-$backupTimestamp
fi

if test -e nixpkgs -a ! -e nixpkgs/.svn; then
    mv nixpkgs${CHECKOUT_SUFFIX} nixpkgs-$backupTimestamp
fi

if test -e services -a ! -e services/.svn; then
    mv nixos/services services-$backupTimestamp
fi

# Check out the NixOS and Nixpkgs sources.
svn co https://svn.cs.uu.nl:12443/repos/trace/nixos/trunk nixos${CHECKOUT_SUFFIX}
svn co https://svn.cs.uu.nl:12443/repos/trace/nixpkgs/${CHECKOUT_BRANCH:-trunk} nixpkgs${CHECKOUT_SUFFIX}
svn co https://svn.cs.uu.nl:12443/repos/trace/services/trunk services

# Add a few required symlink.
ln -sfn ../services nixos${CHECKOUT_SUFFIX}/services
ln -sfn ../nixpkgs${CHECKOUT_SUFFIX}/pkgs nixos${CHECKOUT_SUFFIX}/pkgs
