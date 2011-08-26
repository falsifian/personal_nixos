{ pkgs, ... }:

{
  nodes = {
    server = 
      { pkgs, config, ... }:
      
      {
        services.tomcat.enable = true;
        services.httpd.enable = true;
        services.httpd.adminAddr = "foo@bar.com";
        services.httpd.extraSubservices = [
          { serviceType = "tomcat-connector";
            stateDir = "/var/run/httpd";
            logDir = "/var/log/httpd";
          }
        ];
      };
      
    client = { };
  };
  
  testScript = ''
    startAll;

    $server->waitForJob("tomcat");
    $server->sleep(30); # Dirty, but it takes a while before Tomcat handles to requests properly
    $client->mustSucceed("curl --fail http://server/examples/servlets/servlet/HelloWorldExample");
    $client->mustSucceed("curl --fail http://server/examples/jsp/jsp2/simpletag/hello.jsp");
  '';
}
