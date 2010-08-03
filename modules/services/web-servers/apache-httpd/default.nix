{ config, pkgs, servicesPath, ... }:

with pkgs.lib;

let

  mainCfg = config.services.httpd;
  
  startingDependency = if config.services.gw6c.enable then "gw6c" else "network-interfaces";

  httpd = pkgs.apacheHttpd;

  getPort = cfg: if cfg.port != 0 then cfg.port else if cfg.enableSSL then 443 else 80;

  extraModules = attrByPath ["extraModules"] [] mainCfg;
  extraForeignModules = filter builtins.isAttrs extraModules;
  extraApacheModules = filter (x: !(builtins.isAttrs x)) extraModules; # I'd prefer using builtins.isString here, but doesn't exist yet

  
  makeServerInfo = cfg: {
    # Canonical name must not include a trailing slash.
    canonicalName =
      (if cfg.enableSSL then "https" else "http") + "://" +
      cfg.hostName +
      (if getPort cfg != (if cfg.enableSSL then 443 else 80) then ":${toString (getPort cfg)}" else "");

    # Admin address: inherit from the main server if not specified for
    # a virtual host.
    adminAddr = if cfg.adminAddr != "" then cfg.adminAddr else mainCfg.adminAddr;

    vhostConfig = cfg;
    serverConfig = mainCfg;
    fullConfig = config; # machine config
  };


  vhostOptions = import ./per-server-options.nix {
    inherit mkOption;
    forMainServer = false;
  };

  vhosts = let
    makeVirtualHost = cfgIn: 
      let
        # Fill in defaults for missing options.
        cfg = addDefaultOptionValues vhostOptions cfgIn;
      in cfg;
    in map makeVirtualHost mainCfg.virtualHosts;


  allHosts = [mainCfg] ++ vhosts;
    

  callSubservices = serverInfo: defs:
    let f = svc:
      let 
        svcFunction =
          if svc ? function then svc.function
          else import "${./.}/${if svc ? serviceType then svc.serviceType else svc.serviceName}.nix";
        config = addDefaultOptionValues res.options
          (if svc ? config then svc.config else svc);
        defaults = {
          extraConfig = "";
          extraModules = [];
          extraModulesPre = [];
          extraPath = [];
          extraServerPath = [];
          globalEnvVars = [];
          robotsEntries = "";
          startupScript = "";
          enablePHP = false;
          phpOptions = "";
          options = {};
        };
        res = defaults // svcFunction {inherit config pkgs serverInfo servicesPath;};
      in res;
    in map f defs;


  # !!! callSubservices is expensive   
  subservicesFor = cfg: callSubservices (makeServerInfo cfg) cfg.extraSubservices;

  mainSubservices = subservicesFor mainCfg;

  allSubservices = mainSubservices ++ concatMap subservicesFor vhosts;


  # !!! should be in lib
  writeTextInDir = name: text:
    pkgs.runCommand name {inherit text;} "ensureDir $out; echo -n \"$text\" > $out/$name";


  enableSSL = any (vhost: vhost.enableSSL) allHosts;
  

  # Names of modules from ${httpd}/modules that we want to load.
  apacheModules = 
    [ # HTTP authentication mechanisms: basic and digest.
      "auth_basic" "auth_digest"

      # Authentication: is the user who he claims to be?
      "authn_file" "authn_dbm" "authn_anon" "authn_alias"

      # Authorization: is the user allowed access?
      "authz_user" "authz_groupfile" "authz_host"

      # Other modules.
      "ext_filter" "include" "log_config" "env" "mime_magic"
      "cern_meta" "expires" "headers" "usertrack" /* "unique_id" */ "setenvif"
      "mime" "dav" "status" "autoindex" "asis" "info" "cgi" "dav_fs"
      "vhost_alias" "negotiation" "dir" "imagemap" "actions" "speling"
      "userdir" "alias" "rewrite" "proxy" "proxy_http"
    ] 
    ++ optional enableSSL "ssl"
    ++ extraApacheModules;
    

  loggingConf = ''
    ErrorLog ${mainCfg.logDir}/error_log

    LogLevel notice

    LogFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"" combined
    LogFormat "%h %l %u %t \"%r\" %>s %b" common
    LogFormat "%{Referer}i -> %U" referer
    LogFormat "%{User-agent}i" agent

    CustomLog ${mainCfg.logDir}/access_log ${mainCfg.logFormat}
  '';


  browserHacks = ''
    BrowserMatch "Mozilla/2" nokeepalive
    BrowserMatch "MSIE 4\.0b2;" nokeepalive downgrade-1.0 force-response-1.0
    BrowserMatch "RealPlayer 4\.0" force-response-1.0
    BrowserMatch "Java/1\.0" force-response-1.0
    BrowserMatch "JDK/1\.0" force-response-1.0
    BrowserMatch "Microsoft Data Access Internet Publishing Provider" redirect-carefully
    BrowserMatch "^WebDrive" redirect-carefully
    BrowserMatch "^WebDAVFS/1.[012]" redirect-carefully
    BrowserMatch "^gnome-vfs" redirect-carefully
  '';


  sslConf = ''
    SSLSessionCache dbm:${mainCfg.stateDir}/ssl_scache

    SSLMutex file:${mainCfg.stateDir}/ssl_mutex

    SSLRandomSeed startup builtin
    SSLRandomSeed connect builtin
  '';


  mimeConf = ''
    TypesConfig ${httpd}/conf/mime.types

    AddType application/x-x509-ca-cert .crt
    AddType application/x-pkcs7-crl    .crl
    AddType application/x-httpd-php    .php .phtml

    <IfModule mod_mime_magic.c>
        MIMEMagicFile ${httpd}/conf/magic
    </IfModule>

    AddEncoding x-compress Z
    AddEncoding x-gzip gz tgz
  '';


  perServerConf = isMainServer: cfg: let

    serverInfo = makeServerInfo cfg;

    subservices = callSubservices serverInfo cfg.extraSubservices;

    documentRoot = if cfg.documentRoot != null then cfg.documentRoot else
      pkgs.runCommand "empty" {} "ensureDir $out";

    documentRootConf = ''
      DocumentRoot "${documentRoot}"

      <Directory "${documentRoot}">
          Options Indexes FollowSymLinks
          AllowOverride None
          Order allow,deny
          Allow from all
      </Directory>
    '';

    robotsTxt = pkgs.writeText "robots.txt" ''
      ${# If this is a vhost, the include the entries for the main server as well.
        if isMainServer then ""
        else concatMapStrings (svc: svc.robotsEntries) mainSubservices}
      ${concatMapStrings (svc: svc.robotsEntries) subservices}
    '';

    robotsConf = ''
      Alias /robots.txt ${robotsTxt}
    '';

  in ''
    ServerName ${serverInfo.canonicalName}

    ${concatMapStrings (alias: "ServerAlias ${alias}\n") cfg.serverAliases}

    ${if cfg.sslServerCert != "" then ''
      SSLCertificateFile ${cfg.sslServerCert}
      SSLCertificateKeyFile ${cfg.sslServerKey}
    '' else ""}
    
    ${if cfg.enableSSL then ''
      SSLEngine on
    '' else if enableSSL then /* i.e., SSL is enabled for some host, but not this one */
    ''
      SSLEngine off
    '' else ""}

    ${if isMainServer || cfg.adminAddr != "" then ''
      ServerAdmin ${cfg.adminAddr}
    '' else ""}

    ${if !isMainServer && mainCfg.logPerVirtualHost then ''
      ErrorLog ${mainCfg.logDir}/error_log-${cfg.hostName}
      CustomLog ${mainCfg.logDir}/access_log-${cfg.hostName} ${mainCfg.logFormat}
    '' else ""}

    ${robotsConf}

    ${if isMainServer || cfg.documentRoot != null then documentRootConf else ""}

    ${if cfg.enableUserDir then ''
    
      UserDir public_html
      UserDir disabled root
      
      <Directory "/home/*/public_html">
          AllowOverride FileInfo AuthConfig Limit Indexes
          Options MultiViews Indexes SymLinksIfOwnerMatch IncludesNoExec
          <Limit GET POST OPTIONS>
              Order allow,deny
              Allow from all
          </Limit>
          <LimitExcept GET POST OPTIONS>
              Order deny,allow
              Deny from all
          </LimitExcept>
      </Directory>
      
    '' else ""}

    ${if cfg.globalRedirect != "" then ''
      RedirectPermanent / ${cfg.globalRedirect}
    '' else ""}

    ${
      let makeFileConf = elem: ''
            Alias ${elem.urlPath} ${elem.file}
          '';
      in concatMapStrings makeFileConf cfg.servedFiles
    }

    ${
      let makeDirConf = elem: ''
            Alias ${elem.urlPath} ${elem.dir}/
            <Directory ${elem.dir}>
                Options +Indexes
                Order allow,deny
                Allow from all
                AllowOverride All
            </Directory>
          '';
      in concatMapStrings makeDirConf cfg.servedDirs
    }

    ${concatMapStrings (svc: svc.extraConfig) subservices}

    ${cfg.extraConfig}
  '';

  
  httpdConf = pkgs.writeText "httpd.conf" ''
  
    ServerRoot ${httpd}

    PidFile ${mainCfg.stateDir}/httpd.pid

    <IfModule prefork.c>
        MaxClients           ${toString mainCfg.maxClients}
        MaxRequestsPerChild  ${toString mainCfg.maxRequestsPerChild}
    </IfModule>

    ${let
        ports = map getPort allHosts;
        uniquePorts = uniqList {inputList = ports;};
      in concatMapStrings (port: "Listen ${toString port}\n") uniquePorts
    }

    User ${mainCfg.user}
    Group ${mainCfg.group}

    ${let
        load = {name, path}: "LoadModule ${name}_module ${path}\n";
        allModules =
          concatMap (svc: svc.extraModulesPre) allSubservices
          ++ map (name: {inherit name; path = "${httpd}/modules/mod_${name}.so";}) apacheModules
          ++ optional enablePHP { name = "php5"; path = "${pkgs.php}/modules/libphp5.so"; }
          ++ concatMap (svc: svc.extraModules) allSubservices 
          ++ extraForeignModules;
      in concatMapStrings load allModules
    }

    AddHandler type-map var

    <Files ~ "^\.ht">
        Order allow,deny
        Deny from all
    </Files>

    ${mimeConf}
    ${loggingConf}
    ${browserHacks}

    Include ${httpd}/conf/extra/httpd-default.conf
    Include ${httpd}/conf/extra/httpd-autoindex.conf
    Include ${httpd}/conf/extra/httpd-multilang-errordoc.conf
    Include ${httpd}/conf/extra/httpd-languages.conf
    
    ${if enableSSL then sslConf else ""}

    # Fascist default - deny access to everything.
    <Directory />
        Options FollowSymLinks
        AllowOverride None
        Order deny,allow
        Deny from all
    </Directory>

    # But do allow access to files in the store so that we don't have
    # to generate <Directory> clauses for every generated file that we
    # want to serve.
    <Directory /nix/store>
        Order allow,deny
        Allow from all
    </Directory>

    # Generate directives for the main server.
    ${perServerConf true mainCfg}
    
    # Always enable virtual hosts; it doesn't seem to hurt.
    ${let
        ports = map getPort allHosts;
        uniquePorts = uniqList {inputList = ports;};
      in concatMapStrings (port: "NameVirtualHost *:${toString port}\n") uniquePorts
    }

    ${let
        makeVirtualHost = vhost: ''
          <VirtualHost *:${toString (getPort vhost)}>
              ${perServerConf false vhost}
          </VirtualHost>
        '';
      in concatMapStrings makeVirtualHost vhosts
    }
  '';


  enablePHP = any (svc: svc.enablePHP) allSubservices;


  # Generate the PHP configuration file.  Should probably be factored
  # out into a separate module.
  phpIni = pkgs.runCommand "php.ini"
    { options = concatStringsSep "\n"
        ([ mainCfg.phpOptions ] ++ (map (svc: svc.phpOptions) allSubservices));
    }
    ''
      cat ${pkgs.php}/etc/php-recommended.ini > $out
      echo "$options" >> $out
    '';

in


{

  ###### interface

  options = {
  
    services.httpd = {
      
      enable = mkOption {
        default = false;
        description = "
          Whether to enable the Apache httpd server.
        ";
      };

      extraConfig = mkOption {
        default = "";
        description = "
          These configuration lines will be passed verbatim to the apache config
        ";
      };

      extraModules = mkOption {
        default = [];
        example = [ "proxy_connect" { name = "php5"; path = "${pkgs.php}/modules/libphp5.so"; } ];
        description = ''
          Specifies additional Apache modules.  These can be specified
          as a string in the case of modules distributed with Apache,
          or as an attribute set specifying the
          <varname>name</varname> and <varname>path</varname> of the
          module.
        '';
      };

      logPerVirtualHost = mkOption {
        default = false;
        description = "
          If enabled, each virtual host gets its own
          <filename>access_log</filename> and
          <filename>error_log</filename>, namely suffixed by the
          <option>hostName</option> of the virtual host.
        ";
      };

      user = mkOption {
        default = "wwwrun";
        description = "
          User account under which httpd runs.  The account is created
          automatically if it doesn't exist.
        ";
      };

      group = mkOption {
        default = "wwwrun";
        description = "
          Group under which httpd runs.  The account is created
          automatically if it doesn't exist.
        ";
      };

      logDir = mkOption {
        default = "/var/log/httpd";
        description = "
          Directory for Apache's log files.  It is created automatically.
        ";
      };

      logFormat = mkOption {
        default = "common";
        example = "combined";
        description = "
          Log format for Apache's log files. Possible values are: combined, common, referer, agent.
        ";
      };

      stateDir = mkOption {
        default = "/var/run/httpd";
        description = "
          Directory for Apache's transient runtime state (such as PID
          files).  It is created automatically.  Note that the default,
          <filename>/var/run/httpd</filename>, is deleted at boot time.
        ";
      };

      virtualHosts = mkOption {
        default = [];
        example = [
          { hostName = "foo";
            documentRoot = "/data/webroot-foo";
          }
          { hostName = "bar";
            documentRoot = "/data/webroot-bar";
          }
        ];
        description = ''
          Specification of the virtual hosts served by Apache.  Each
          element should be an attribute set specifying the
          configuration of the virtual host.  The available options
          are the non-global options permissible for the main host.
        '';
      };

      phpOptions = mkOption {
        default = "";
        example =
          ''
            date.timezone = "CET"
          '';
        description =
          "Options appended to the PHP configuration file <filename>php.ini</filename>.";
      };

      maxClients = mkOption {
        default = 150;
        example = 8;
        description = "Maximum number of httpd processes (prefork)";
      };

      maxRequestsPerChild = mkOption {
        default = 0;
        example = 500;
        description =
          "Maximum number of httpd requests answered per httpd child (prefork), 0 means unlimited";
      };
    }

    # Include the options shared between the main server and virtual hosts.
    // (import ./per-server-options.nix {
      inherit mkOption;
      forMainServer = true;
    });

  };


  ###### implementation

  config = mkIf config.services.httpd.enable {

    users.extraUsers = singleton
      { name = mainCfg.user;
        description = "Apache httpd user";
      };

    users.extraGroups = singleton
      { name = mainCfg.group;
      };

    environment.systemPackages = [httpd] ++ concatMap (svc: svc.extraPath) allSubservices;

    services.httpd.phpOptions =
      ''
        ; Needed for PHP's mail() function.
        sendmail_path = sendmail -t -i

        ; Apparently PHP doesn't use $TZ.
        date.timezone = "${config.time.timeZone}"
      '';

    jobs.httpd =
      { # Statically verify the syntactic correctness of the generated
        # httpd.conf.  !!! this is impure!  It doesn't just check for
        # syntax, but also whether the Apache user/group exist,
        # whether SSL keys exist, etc.
        buildHook =
          ''
            echo
            echo '=== Checking the generated Apache configuration file ==='
            ${httpd}/bin/httpd -f ${httpdConf} -t || true
          '';

        description = "Apache HTTPD";

        startOn = "started ${startingDependency}";

        environment =
          { # !!! This should be added in test-instrumentation.nix.  It
            # shouldn't hurt though, since packages usually aren't built
            # with coverage enabled.
           GCOV_PREFIX = "/tmp/coverage-data";

           PATH = concatStringsSep ":" (
             [ "${pkgs.coreutils}/bin" "${pkgs.gnugrep}/bin" ]
             ++ # Needed for PHP's mail() function.  !!! Probably the
                # ssmtp module should export the path to sendmail in
                # some way.
                optional config.networking.defaultMailServer.directDelivery "${pkgs.ssmtp}/sbin"
             ++ (concatMap (svc: svc.extraServerPath) allSubservices) );

           PHPRC = if enablePHP then phpIni else "";

           TZ = config.time.timeZone;

          } // (listToAttrs (concatMap (svc: svc.globalEnvVars) allSubservices));

        preStart =
          ''
            mkdir -m 0700 -p ${mainCfg.stateDir}
            mkdir -m 0700 -p ${mainCfg.logDir}

            ${optionalString (mainCfg.documentRoot != null)
            ''
              # Create the document root directory if does not exists yet
              mkdir -p ${mainCfg.documentRoot}
            ''
            }

            # Get rid of old semaphores.  These tend to accumulate across
            # server restarts, eventually preventing it from restarting
            # succesfully.
            for i in $(${pkgs.utillinux}/bin/ipcs -s | grep ' ${mainCfg.user} ' | cut -f2 -d ' '); do
                ${pkgs.utillinux}/bin/ipcrm -s $i
            done

            # Run the startup hooks for the subservices.
            for i in ${toString (map (svn: svn.startupScript) allSubservices)}; do
                echo Running Apache startup hook $i...
                $i
            done
          '';

        daemonType = "fork";

        exec = "${httpd}/bin/httpd -f ${httpdConf}";

        preStop =
          ''
            ${httpd}/bin/httpd -f ${httpdConf} -k graceful-stop
          '';
      };

  };
  
}
