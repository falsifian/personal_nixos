#! @shell@ -e
set -x

# Obtain Subversion.
if test -z "$(type -tp svn)"; then
    #nix-channel --add http://nix.cs.uu.nl/dist/nix/channels-v3/nixpkgs-unstable
    #nix-channel --update
    nix-env -i subversion
fi

cd /etc/nixos

# Move any old nixos or nixpkgs directories out of the way.
backupTimestamp=$(date "+%Y%m%d%H%M%S")

if test -e nixos -a ! -e nixos/.svn; then
    mv nixos nixos-$backupTimestamp
fi

if test -e nixpkgs -a ! -e nixpkgs/.svn; then
    mv nixpkgs nixpkgs-$backupTimestamp
fi

if test -e services -a ! -e services/.svn; then
    mv nixos/services services-$backupTimestamp
fi

# Check out the NixOS and Nixpkgs sources.
svn co https://svn.cs.uu.nl:12443/repos/trace/nixos/trunk nixos
svn co https://svn.cs.uu.nl:12443/repos/trace/nixpkgs/trunk nixpkgs
svn co https://svn.cs.uu.nl:12443/repos/trace/services/trunk services
ln -sfn ../services nixos/services

# A few symlink.
ln -sfn ../nixpkgs/pkgs nixos/pkgs
ln -sfn nixpkgs/pkgs/top-level/all-packages.nix install-source.nix
