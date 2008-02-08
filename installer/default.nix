{pkgs, config, nix}:

let

  makeProg = args: pkgs.substituteAll (args // {
    dir = "bin";
    isExecutable = true;
  });

in

{

  nixosInstall = makeProg {
    name = "nixos-install";
    src = ./nixos-install.sh;

    inherit (pkgs) perl;
    inherit nix;
    nixpkgsURL = config.installer.nixpkgsURL;

    pathsFromGraph = ../helpers/paths-from-graph.pl;

    nixClosure = pkgs.runCommand "closure"
      {exportReferencesGraph = ["refs" nix];}
      "cp refs $out";
  };

  nixosRebuild = makeProg {
    name = "nixos-rebuild";
    src = ./nixos-rebuild.sh;
  };

  nixosCheckout = makeProg {
    name = "nixos-checkout";
    src = ./nixos-checkout.sh;
   };

  nixosHardwareScan = makeProg {
    name = "nixos-hardware-scan";
    src = ./nixos-hardware-scan.pl;
    inherit (pkgs) perl;
  };

}
