#! /bin/sh
nix-channel --add http://nix.cs.uu.nl/dist/nix/channels-v3/nixpkgs-unstable
nix-channel --update
nix-env -i subversion
cd /etc/nixos
svn co https://svn.cs.uu.nl:12443/repos/trace/nixos/trunk nixos
svn co https://svn.cs.uu.nl:12443/repos/trace/nixpkgs/trunk nixpkgs
ln -sf ../nixpkgs/pkgs nixos/pkgs
ln -sf nixpkgs/pkgs/top-level/all-packages.nix install-source.nix
