{ nixpkgs ? ../../nixpkgs
, services ? ../../services
, system ? builtins.currentSystem
}:

with import ../lib/testing.nix { inherit nixpkgs services system; };

{
  avahi = makeTest (import ./avahi.nix);
  bittorrent = makeTest (import ./bittorrent.nix);
  firefox = makeTest (import ./firefox.nix);
  firewall = makeTest (import ./firewall.nix);
  installer = makeTests (import ./installer.nix);
  ipv6 = makeTest (import ./ipv6.nix);
  kde4 = makeTest (import ./kde4.nix);
  login = makeTest (import ./login.nix);
  nat = makeTest (import ./nat.nix);
  nfs = makeTest (import ./nfs.nix);
  openssh = makeTest (import ./openssh.nix);
  portmap = makeTest (import ./portmap.nix);
  proxy = makeTest (import ./proxy.nix);
  quake3 = makeTest (import ./quake3.nix);
  remote_builds = makeTest (import ./remote-builds.nix);
  simple = makeTest (import ./simple.nix);
  subversion = makeTest (import ./subversion.nix);
  trac = makeTest (import ./trac.nix);
  xfce = makeTest (import ./xfce.nix);
}
