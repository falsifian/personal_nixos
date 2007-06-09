{ stdenv, writeText, lib, xorg, mesa, xterm, slim, gnome
, compiz, feh
, kdelibs, kdebase
, xkeyboard_config
, openssh, x11_ssh_askpass
, nvidiaDrivers, libX11, libXext

, config

, # Virtual console for the X server.
  tty ? 7

, # X display number.
  display ? 0

, # List of font directories.
  fontDirectories

}:

let

  getCfg = option: config.get ["services" "xserver" option];
  getCfg2 = option: config.get (["services" "xserver"] ++ option);

  optional = condition: x: if condition then [x] else [];

  #Beryl parameters
  #berylcore
  #berylmanager
  #berylemerald

  # Get a bunch of user settings.
  videoDriver = getCfg "videoDriver";
  resolutions = map (res: "\"${toString res.x}x${toString res.y}\"") (getCfg "resolutions");
  sessionType = getCfg "sessionType";
  sessionStarter = getCfg "sessionStarter";


  sessionCmd =
    if sessionType == "" then sessionStarter else
    if sessionType == "xterm" then "${xterm}/bin/xterm -ls" else
    if sessionType == "gnome" then "${gnome.gnometerminal}/bin/gnome-terminal -ls" else
    abort ("unknown session type "+ sessionType);


  windowManager =
    let wm = getCfg "windowManager"; in
    if wm != "" then wm else
    if sessionType == "gnome" then "metacity" else
    if sessionType == "kde" then "none" /* started by startkde */ else
    "twm";

    
  modules = 
    optional (videoDriver == "nvidia") nvidiaDrivers ++       #make sure it first loads the nvidia libs
    [
      xorg.xorgserver
      xorg.xf86inputkeyboard
      xorg.xf86inputmouse
    ] 
    ++ optional (videoDriver == "vesa") xorg.xf86videovesa
    ++ optional (videoDriver == "i810") xorg.xf86videoi810
    ++ optional (videoDriver == "intel") xorg.xf86videointel;

    
  configFile = stdenv.mkDerivation {
    name = "xserver.conf";
    src = ./xserver.conf;
    inherit fontDirectories videoDriver resolutions;
    buildCommand = "
      buildCommand= # urgh, don't substitute this

      export fontPaths=
      for i in $fontDirectories; do
        if test \"\${i:0:\${#NIX_STORE}}\" == \"$NIX_STORE\"; then
          for j in $(find $i -name fonts.dir); do
            fontPaths=\"\${fontPaths}FontPath \\\"$(dirname $j)\\\"\\n\"
          done
        fi
      done

      export modulePaths=
      for i in $(find ${toString modules} -type d); do
        if ls $i/*.so 2> /dev/null; then
          modulePaths=\"\${modulePaths}ModulePath \\\"$i\\\"\\n\"
        fi
      done

      #if only my gf were this dirty
      if test \"${toString videoDriver}\" == \"nvidia\"; then
        export moduleSection=\"Load  \\\"glx\\\" \\n \\
 SubSection \\\"extmod\\\" \\n \\
 Option \\\"omit xfree86-dga\\\" \\n \\
 EndSubSection \\n \"

        export screen=\"Option  \\\"AddARGBGLXVisuals\\\" \\\"true\\\" \\n \\
 Option  \\\"DisableGLXRootClipping\\\" \\\"true\\\" \\n \"
        export device=\"Option       \\\"RenderAccel\\\" \\\"true\\\" \\n \\
 Option       \\\"AllowGLXWithComposite\\\" \\\"true\\\" \\n \\
 Option       \\\"AddARGBGLXVisuals\\\"     \\\"true\\\" \\n \"
        export extensions=\"Option       \\\"Composite\\\" \\\"Enable\\\" \\n \"

      else
        export moduleSection='Load \"glx\" \\n \\
          Load \"dri\" '
        export screen=
        export device=
        export extensions=
      fi

      substituteAll $src $out
    ";
  };


  clientScript = writeText "xclient" "

    source /etc/profile

    exec > $HOME/.Xerrors 2>&1


    ### Load X defaults.
    if test -e ~/.Xdefaults; then
      ${xorg.xrdb}/bin/xrdb -merge ~/.Xdefaults
    fi


    ${if getCfg "startSSHAgent" then "
      ### Start the SSH agent.
      export SSH_ASKPASS=${x11_ssh_askpass}/libexec/x11-ssh-askpass
      eval $(${openssh}/bin/ssh-agent)
    " else ""}
  

    ### Start a window manager.
  
    ${if windowManager == "twm" then "
      ${xorg.twm}/bin/twm &
    "

    else if windowManager == "metacity" then "
      env LD_LIBRARY_PATH=${libX11}/lib:${libXext}/lib:/usr/lib/
      # !!! Hack: load the schemas for Metacity.
      GCONF_CONFIG_SOURCE=xml::~/.gconf ${gnome.GConf}/bin/gconftool-2 \\
        --makefile-install-rule ${gnome.metacity}/etc/gconf/schemas/*.schemas
      ${gnome.metacity}/bin/metacity &
    "

    else if windowManager == "kwm" then "
      ${kdebase}/bin/kwin &
    "

    else if windowManager == "compiz" then "
    
      # !!! Hack: load the schemas for Compiz.
      GCONF_CONFIG_SOURCE=xml::~/.gconf ${gnome.GConf}/bin/gconftool-2 \\
        --makefile-install-rule ${compiz}/etc/gconf/schemas/*.schemas

      # !!! Hack: turn on most Compiz modules.
      ${gnome.GConf}/bin/gconftool-2 -t list --list-type=string \\
        --set /apps/compiz/general/allscreens/options/active_plugins \\
        [gconf,png,decoration,wobbly,fade,minimize,move,resize,cube,switcher,rotate,place,scale,water]

      # Start Compiz and the GTK-style window decorator.
      env LD_LIBRARY_PATH=${libX11}/lib:${libXext}/lib:/usr/lib/
      ${compiz}/bin/compiz gconf &
      ${compiz}/bin/gtk-window-decorator --sync &
    "
    #else if windowManager == "beryl" then "
    #  ${berylmanager}/bin/beryl-manager &
    #"

    else if windowManager == "none" then "

      # The session starter will start the window manager.

    "

    else abort ("unknown window manager " + windowManager)}


    ### Show a background image.
    # (but not if we're starting a full desktop environment that does it for us)
    ${if sessionType != "kde" then "
    
      if test -e $HOME/.background-image; then
        ${feh}/bin/feh --bg-scale $HOME/.background-image
      fi
      
    " else ""}
    

    ### Start the session.
    ${if sessionType == "kde" then "

      # Start KDE.
      export KDEDIRS=${kdebase}:${kdelibs}
      export XDG_CONFIG_DIRS=${kdebase}/etc/xdg:${kdelibs}/etc/xdg
      export XDG_DATA_DIRS=${kdebase}/share
      exec ${kdebase}/bin/startkde

    " else "

      # For all other session types, we currently just start a
      # terminal of the kind indicated by sessionCmd.
      # !!! yes, this means that you 'log out' by killing the X server.
      while ${sessionCmd}; do
        sleep 1  
      done

    "}
    
  "; # */ <- hack to fix syntax highlighting


  xserverArgs = [
    "-ac"
    "-logverbose"
    "-verbose"
    "-nolisten tcp"
    "-terminate"
    "-logfile" "/var/log/X.${toString display}.log"
    "-config ${configFile}"
    ":${toString display}" "vt${toString tty}"
    "-xkbdir" "${xkeyboard_config}/etc/X11/xkb"
  ];

  
  # Note: lines must not be indented.
  slimConfig = writeText "slim.cfg" "
xauth_path ${xorg.xauth}/bin/xauth
default_xserver ${xorg.xorgserver}/bin/X
xserver_arguments ${toString xserverArgs}
login_cmd exec ${stdenv.bash}/bin/sh ${clientScript}
  ";


  # Unpack the SLiM theme, or use the default.
  slimThemesDir =
    let
      theme = getCfg2 ["slim" "theme"];
      unpackedTheme = stdenv.mkDerivation {
        name = "slim-theme";
        buildCommand = "
          ensureDir $out
          cd $out
          unpackFile ${theme}
          ln -s * default
        ";
      };
    in if theme == null then "${slim}/share/slim/themes" else unpackedTheme;       


in


rec {
  name = "xserver";

  
  extraPath = [
    xorg.xrandr
    xorg.xrdb
    xorg.setxkbmap
    feh
  ]
  ++ optional (windowManager == "twm") [
    xorg.twm
  ]
  ++ optional (windowManager == "metacity") [
    gnome.metacity
  ]
  ++ optional (windowManager == "compiz") [
    compiz
  ]
  #++ optional (windowManager == "beryl") [
  #  berylcore berylmanager berylemerald
  #]
  ++ optional (sessionType == "xterm") [
    xterm
  ]
  ++ optional (sessionType == "gnome") [
    gnome.gnometerminal
    gnome.GConf
    gnome.gconfeditor
  ]
  ++ optional (sessionType == "kde") [
    kdelibs
    kdebase
    xorg.iceauth # absolutely required by dcopserver
    xorg.xset # used by startkde, non-essential
  ];


  extraEtc =
    optional (sessionType == "kde")
      { source = "${xkeyboard_config}/etc/X11/xkb";
        target = "X11/xkb";
      };

    
  job = "
    start on network-interfaces

    start script
    
      rm -f /var/run/opengl-driver
      ${if videoDriver == "nvidia"        
        then "ln -sf ${nvidiaDrivers} /var/run/opengl-driver"
	else if getCfg "driSupport"
        then "ln -sf ${mesa} /var/run/opengl-driver"
        else ""
       }

       rm -f /var/log/slim.log
       
    end script

    env SLIM_CFGFILE=${slimConfig}
    env SLIM_THEMESDIR=${slimThemesDir}
    env FONTCONFIG_FILE=/etc/fonts/fonts.conf  				# !!! cleanup
    env XKB_BINDIR=${xorg.xkbcomp}/bin         				# Needed for the Xkb extension.
    env LD_LIBRARY_PATH=${libX11}/lib:${libXext}/lib:/usr/lib/          # related to xorg-sys-opengl - needed to load libglx for (AI)GLX support (for compiz)

    ${if videoDriver == "nvidia"
      then "env XORG_DRI_DRIVER_PATH=${nvidiaDrivers}/X11R6/lib/modules/drivers/"
      else if getCfg "driSupport"
      then "env XORG_DRI_DRIVER_PATH=${mesa}/lib/modules/dri"
      else ""
    } 

    exec ${slim}/bin/slim
  ";
  
}
