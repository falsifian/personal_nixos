# From an end-user configuration file (`configuration'), build a NixOS
# configuration object (`config') from which we can retrieve option
# values.

{ system ? builtins.currentSystem
, nixpkgs ? import ./from-env.nix "NIXPKGS" /etc/nixos/nixpkgs
, pkgs ? null
, baseModules ? import ../modules/module-list.nix
, extraArgs ? {}
, modules
}:

let extraArgs_ = extraArgs; pkgs_ = pkgs; in

rec {

  # These are the NixOS modules that constitute the system configuration.
  configComponents = modules ++ baseModules;

  # Merge the option definitions in all modules, forming the full
  # system configuration.  This is called "configFast" because it's
  # not checked for undeclared options.
  configFast =
    pkgs.lib.definitionsOf configComponents extraArgs;

  # These are the extra arguments passed to every module.  In
  # particular, Nixpkgs is passed through the "pkgs" argument.
  extraArgs = extraArgs_ // {
    inherit pkgs optionDeclarations;
    modulesPath = ../modules;
  };

  # Import Nixpkgs, allowing the NixOS option nixpkgs.config to
  # specify the Nixpkgs configuration (e.g., to set package options
  # such as firefox.enableGeckoMediaPlayer, or to apply global
  # overrides such as changing GCC throughout the system).  This is
  # tricky, because we have to prevent an infinite recursion: "pkgs"
  # is passed as an argument to NixOS modules, but the value of "pkgs"
  # depends on config.nixpkgs.config, which we get from the modules.
  # So we call ourselves here with "pkgs" explicitly set to an
  # instance that doesn't depend on nixpkgs.config.
  pkgs =
    if pkgs_ != null
    then pkgs_
    else import nixpkgs {
      inherit system;
      config =
        (import ./eval-config.nix {
          inherit system nixpkgs extraArgs modules;
          # For efficiency, leave out most NixOS modules; they don't
          # define nixpkgs.config, so it's pointless to evaluate them.
          baseModules = [ ../modules/misc/nixpkgs.nix ];
          pkgs = import nixpkgs { inherit system; config = {}; };
        }).configFast.nixpkgs.config;
    };

  # "fixableDeclarationsOf" is used instead of "declarationsOf" because some
  # option default values may depends on the definition of other options.
  # !!! This seems inefficent.  Didn't definitionsOf already compute
  # the option declarations?
  optionDeclarations =
    pkgs.lib.fixableDeclarationsOf configComponents extraArgs configFast;

  # Optionally check wether all config values have corresponding
  # option declarations.
  config = pkgs.checker configFast
    configFast.environment.checkConfigurationOptions
    optionDeclarations configFast;
}
