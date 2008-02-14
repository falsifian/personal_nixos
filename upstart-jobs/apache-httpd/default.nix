{config, pkgs}:

let

  cfg = config.services.httpd;
  
  startingDependency = if config.services.gw6c.enable then "gw6c" else "network-interfaces";

  httpd = pkgs.apacheHttpd;


  serverInfo = {
    # Canonical name must not include a trailing slash.
    canonicalName =
      "http://" +
      cfg.hostName +
      (if cfg.httpPort != 80 then ":${toString cfg.httpPort}" else "");
    serverConfig = cfg;
    fullConfig = config; # machine config
  };


  subservices =
    let f = svc:
      let config = pkgs.lib.addDefaultOptionValues res.options svc.config;
          res = svc.function {inherit config pkgs serverInfo;};
      in res;
    in map f cfg.extraSubservices;


  # !!! should be in lib
  writeTextInDir = name: text:
    pkgs.runCommand name {inherit text;} "ensureDir $out; echo -n \"$text\" > $out/$name";
  

  documentRoot = if cfg.documentRoot != null then cfg.documentRoot else
    pkgs.runCommand "empty" {} "ensureDir $out";


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
      "userdir" "alias" "rewrite"
    ] ++ pkgs.lib.optional cfg.enableSSL "ssl_module";
    

  loggingConf = ''
    ErrorLog ${cfg.logDir}/error_log

    LogLevel notice

    LogFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"" combined
    LogFormat "%h %l %u %t \"%r\" %>s %b" common
    LogFormat "%{Referer}i -> %U" referer
    LogFormat "%{User-agent}i" agent

    CustomLog ${cfg.logDir}/access_log common
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
    Listen ${toString cfg.httpsPort}

    SSLSessionCache dbm:${cfg.stateDir}/ssl_scache

    SSLMutex file:${cfg.stateDir}/ssl_mutex

    SSLRandomSeed startup builtin
    SSLRandomSeed connect builtin

    <VirtualHost _default_:${toString cfg.httpsPort}>

        SSLEngine on

        SSLCipherSuite ALL:!ADH:!EXPORT56:RC4+RSA:+HIGH:+MEDIUM:+LOW:+SSLv2:+EXP:+eNULL

        SSLCertificateFile @sslServerCert@
        SSLCertificateKeyFile @sslServerKey@

        #   MSIE compatability.
        SetEnvIf User-Agent ".*MSIE.*" \
                 nokeepalive ssl-unclean-shutdown \
                 downgrade-1.0 force-response-1.0

    </VirtualHost>
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
    ${pkgs.lib.concatStrings (map (svc: svc.robotsEntries) subservices)}
  '';
  
  robotsConf = ''
    Alias /robots.txt ${robotsTxt}
  '';

  
  httpdConf = pkgs.writeText "httpd.conf" ''
  
    ServerRoot ${httpd}

    ServerAdmin ${cfg.adminAddr}

    ServerName ${serverInfo.canonicalName}

    PidFile ${cfg.stateDir}/httpd.pid

    <IfModule prefork.c>
        MaxClients           150
        MaxRequestsPerChild  0
    </IfModule>

    Listen ${toString cfg.httpPort}

    User ${cfg.user}
    Group ${cfg.group}

    ${let
        load = {name, path}: "LoadModule ${name}_module ${path}\n";
        allModules =
          pkgs.lib.concatMap (svc: svc.extraModulesPre) subservices ++
          map (name: {inherit name; path = "${httpd}/modules/mod_${name}.so";}) apacheModules ++
          pkgs.lib.concatMap (svc: svc.extraModules) subservices;
      in pkgs.lib.concatStrings (map load allModules)
    }

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
    
    ${if cfg.enableSSL then sslConf else ""}

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

    ${robotsConf}
    
    ${documentRootConf}

    ${
      let makeDirConf = elem: ''
            Alias ${elem.urlPath} ${elem.dir}/
            <Directory ${elem.dir}>
                Order allow,deny
                Allow from all
                AllowOverride None
            </Directory>
          '';
      in pkgs.lib.concatStrings (map makeDirConf cfg.servedDirs)
    }

    ${
      let makeFileConf = elem: ''
            Alias ${elem.urlPath} ${elem.file}
          '';
      in pkgs.lib.concatStrings (map makeFileConf cfg.servedFiles)
    }

    ${pkgs.lib.concatStrings (map (svc: svc.extraConfig) subservices)}
  '';

    
in

{

  name = "httpd";
  
  users = [
    { name = cfg.user;
      description = "Apache httpd user";
    }
  ];

  groups = [
    { name = cfg.group;
    }
  ];

  extraPath = [httpd] ++ pkgs.lib.concatMap (svc: svc.extraPath) subservices;

  # Statically verify the syntactic correctness of the generated
  # httpd.conf.
  buildHook = ''
    echo
    echo '=== Checking the generated Apache configuration file ==='
    ${httpd}/bin/httpd -f ${httpdConf} -t
  '';

  job = ''
    description "Apache HTTPD"

    start on ${startingDependency}/started
    stop on shutdown

    start script
      mkdir -m 0700 -p ${cfg.stateDir}
      mkdir -m 0700 -p ${cfg.logDir}

      # Get rid of old semaphores.  These tend to accumulate across
      # server restarts, eventually preventing it from restarting
      # succesfully.
      for i in $(${pkgs.utillinux}/bin/ipcs -s | grep ' ${cfg.user} ' | cut -f2 -d ' '); do
        ${pkgs.utillinux}/bin/ipcrm -s $i
      done
    end script

    ${
      let f = {name, value}: "env ${name}=${value}\n";
      in pkgs.lib.concatStrings (map f (pkgs.lib.concatMap (svc: svc.globalEnvVars) subservices))
    }

    env PATH=${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.lib.concatStringsSep ":" (pkgs.lib.concatMap (svc: svc.extraServerPath) subservices)}

    ${pkgs.diffutils}/bin:${pkgs.gnused}/bin

    respawn ${httpd}/bin/httpd -f ${httpdConf} -DNO_DETACH
  '';

}
