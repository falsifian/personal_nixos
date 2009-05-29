{pkgs, config, ...}:

###### interface
let
  inherit (pkgs.lib) mkOption;

  options = {

    fonts = {

      enableFontConfig = mkOption { # !!! should be enableFontconfig
        default = true;
        description = "
          If enabled, a Fontconfig configuration file will be built
          pointing to a set of default fonts.  If you don't care about
          running X11 applications or any other program that uses
          Fontconfig, you can turn this option off and prevent a
          dependency on all those fonts.
        ";
      };

      # should be move elsewhere.
      enableGhostscriptFonts = mkOption {
        default = false;
        description = "
          Whether to add the fonts provided by Ghostscript (such as
          various URW fonts and the ``Base-14'' Postscript fonts) to the
          list of system fonts, making them available to X11
          applications.
        ";
      };

      enableFontDir = mkOption {
        default = false;
        description = "
          Whether to create a directory with links to all fonts in share - 
          so user can configure vncserver script one time (I mean per-user 
          vncserver, so global service is not a good solution).
        ";
      };

      # TODO: find another name for it.
      fonts = mkOption {
        default = [
          # - the user's .fonts directory
          "~/.fonts"
          # - the user's current profile
          "~/.nix-profile/lib/X11/fonts"
          "~/.nix-profile/share/fonts"
          # - the default profile
          "/nix/var/nix/profiles/default/lib/X11/fonts"
          "/nix/var/nix/profiles/default/share/fonts"
        ];
        description = "
          List of primary font paths.
        ";
        apply = list: list ++ [
          # - a few statically built locations
          pkgs.xorg.fontbhttf
          pkgs.xorg.fontbhlucidatypewriter100dpi
          pkgs.xorg.fontbhlucidatypewriter75dpi
          pkgs.ttf_bitstream_vera
          pkgs.freefont_ttf
          pkgs.xorg.fontbh100dpi
          pkgs.xorg.fontmiscmisc
          pkgs.xorg.fontcursormisc
        ]
        ++ pkgs.lib.optional config.fonts.enableCoreFonts pkgs.corefonts
        ++ pkgs.lib.optional config.fonts.enableGhostscriptFonts "${pkgs.ghostscript}/share/ghostscript/fonts"
        ++ config.fonts.extraFonts;
      };

      extraFonts = mkOption {
        default = [];
        description = "
          List of additional fonts.
        ";
      };

      enableCoreFonts = mkOption {
        default = true;
        description = "
          Whether to include MS Core Fonts (redistributable, but only verbatim).
        ";
      };

    };

  };
in

###### implementation
let
  inherit (pkgs) builderDefs ttmkfdir;
  inherit (pkgs.xorg) mkfontdir mkfontscale fontalias;

  fontDirs = config.fonts.fonts;


  localDefs = with builderDefs; builderDefs.passthru.function rec {
    src = "";/* put a fetchurl here */

    buildInputs = [mkfontdir mkfontscale ttmkfdir];
    configureFlags = [];
    inherit fontDirs;
    installPhase = fullDepEntry ("
    list='';
    for i in ${toString fontDirs} ; do
      if [ -d \$i/ ]; then
        list=\"\$list \$i\";
      fi;
    done
    list=\$(find \$list -name fonts.dir);
    fontDirs='';
    for i in \$list ; do
      fontDirs=\"\$fontDirs \$(dirname \$i)\";
    done;
    mkdir -p \$out/share/X11-fonts/; 
    for i in \$(find \$fontDirs -type f -o -type l); do
      j=\${i##*/}
      if ! test -e \$out/share/X11-fonts/\${j}; then
        ln -s \$i \$out/share/X11-fonts/\${j};
      fi;
    done;
    cd \$out/share/X11-fonts/
    rm fonts.dir
    rm fonts.scale
    rm fonts.alias
    mkfontdir
    mkfontscale
    mv fonts.scale fonts.scale.old
    mv fonts.dir fonts.dir.old
    ttmkfdir
    cat fonts.scale.old >> fonts.scale
    cat fonts.dir.old >> fonts.dir
    rm fonts.dir.old
    rm fonts.scale.old
    cat \$( find ${fontalias}/ -name fonts.alias) >fonts.alias
  ") ["minInit" "addInputs"];
  };

  x11Fonts = with localDefs; stdenv.mkDerivation rec {
    name = "X11-fonts";
    builder = writeScript (name + "-builder")
      (textClosure localDefs 
        [installPhase doForceShare doPropagate]);
    meta = {
      description = "
        Directory to contain all X11 fonts requested.
      ";
    };
  };

  inherit (pkgs.lib) mkIf;
in

{
  require = [options];

  system.build.x11Fonts = x11Fonts;

  environment.etc = mkIf config.fonts.enableFontConfig
    [ { # Configuration file for fontconfig used to locate
        # (X11) client-rendered fonts.
        source = pkgs.makeFontsConf {
          fontDirectories = config.fonts.fonts;
        };
        target = "fonts/fonts.conf";
      }
    ];

  environment.shellInit =
    '' 
      export FONTCONFIG_FILE=/etc/fonts/fonts.conf
    '';

  environment.systemPackages =
    pkgs.lib.optional config.fonts.enableFontDir config.system.build.x11Fonts;
}
