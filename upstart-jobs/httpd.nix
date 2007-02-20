{config, pkgs, glibc, pwdutils}:

let

  getCfg = option: config.get ["services" "httpd" option];
  getCfgs = options: config.get (["services" "httpd"] ++ options); 
  getCfgSvn = option: config.get ["services" "httpd" "subservices" "subversion" option];

  optional = conf: subService:
    if conf then [subService] else [];

    
  hostName = getCfg "hostName";
  httpPort = getCfg "httpPort";
  httpsPort = getCfg "httpsPort";
  user = getCfg "user";
  group = getCfg "group";
  adminAddr = getCfg "adminAddr";
  logDir = getCfg "logDir";
  stateDir = getCfg "stateDir";
  enableSSL = false;
  
  webServer = import ../services/apache-httpd {
    inherit (pkgs) stdenv apacheHttpd coreutils;

    inherit hostName httpPort httpsPort
      user group adminAddr logDir stateDir;
    
    subServices =
    
      # The Subversion subservice.
      (optional (getCfgSvn "enable") (
        let dataDir = getCfgSvn "dataDir"; in
        import ../services/subversion {
          reposDir = dataDir + "/repos";
          dbDir = dataDir + "/db";
          distsDir = dataDir + "/dist";
          backupsDir = dataDir + "/backup";
          tmpDir = dataDir + "/tmp";
          
          inherit user group logDir adminAddr;
          
          canonicalName =
            if webServer.enableSSL then
              "https://" + hostName + ":" + (toString httpsPort)
            else
              "http://" + hostName + ":" + (toString httpPort);

          notificationSender = getCfgSvn "notificationSender";
          autoVersioning = getCfgSvn "autoVersioning";
          userCreationDomain = getCfgSvn "userCreationDomain";

          inherit pkgs;
        })
      )
      ++

      (optional (getCfgs ["extraSubservices" "enable"])
        (map (service : service webServer pkgs)
          (getCfgs ["extraSubservices" "services"])
        )
      )
      ;
  };
  
in

{
  name = "httpd";
  
  job = "
description \"Apache HTTPD\"

start on network-interfaces/started
stop on network-interfaces/stop

start script
    if ! ${glibc}/bin/getent group ${group} > /dev/null; then
        ${pwdutils}/sbin/groupadd ${group}
    fi

    if ! ${glibc}/bin/getent passwd ${user} > /dev/null; then
        ${pwdutils}/sbin/useradd -g ${group} -d /var/empty -s /noshell \\
            -c 'Apache httpd user' ${user}
    fi

    ${webServer}/bin/control prepare    
end script

respawn ${webServer}/bin/control run
  ";
  
}
