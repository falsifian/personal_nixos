args : with args;
let 
    inherit (pkgs.lib) id all whatis escapeShellArg concatMapStrings concatMap
      mapAttrs concatLists flattenAttrs filter;
    inherit (builtins) getAttr hasAttr head isAttrs;
in

rec {
  # prepareRepoAttrs adds svn defaults and preparse the repo attribute sets so that they
  # returns in any case:
  # { type = git/svn; 
  #   target = path;
  #   initialize = cmd; # must create target dir, dirname target will exist
  #   update = cmd;     # pwd will be target
  #   default = true/false;
  # }
  prepareRepoAttrs = repo : attrs :
    assert (isAttrs attrs);
    assert (repo + "" == repo); # assert repo is a string
    if (! (attrs ? type)) then 
      throw "repo type is missing of : ${whatis attrs}"
    # prepare svn repo
    else if attrs.type == "svn" then
      let a = { # add svn defaults
                url = "https://svn.nixos.org/repos/nix/${repo}/trunk";
                target = "/etc/nixos/${repo}";
              } // attrs; in
      rec { 
        inherit (a) type target;
        default =  if a ? default then a.default else false;
        initialize = "svn co ${a.url} ${a.target}"; 
        update = initialize; # co is just as fine as svn update
     }
    # prepare git repo
    else  if attrs.type == "git" then # sanity check for existing attrs
      assert (all id (map ( attr : if hasAttr attr attrs then true 
                                     else throw "git repository item is missing attribute ${attr}")
                          [ "target" "initialize" "update" ]
                      ));
    let t = escapeShellArg attrs.target; in
    rec {
      inherit (attrs) type target;
      default =  if attrs ? default then attrs.default else false;
      update = "cd ${t}; ${attrs.update}";
      initialize =  ''
    cd $(dirname ${t}); ${attrs.initialize}
    [ -d ${t} ] || { echo "git initialize failed to create target directory ${t}"; exit 1; }
    ${update}'';
    }
    else throw "unkown repo type ${attrs.type}";

  # apply prepareRepoAttrs on each repo definition
  repos = mapAttrs ( repo : list : map (x : (prepareRepoAttrs repo x) // { inherit repo; } ) list ) config.installer.repos;

  # function returning the default repo (first one having attribute default or head of list)
  defaultRepo = list : head ( (filter ( attrs : attrs ? default && attrs.default == true ) list)
                              ++ list );

  # creates the nixos-checkout script 
  nixosCheckout =
    makeProg {
    name = "nixos-checkout";
    src = pkgs.writeScript "nixos-checkout" (''
          #! @shell@ -e
          # this file is automatically generated from nixos configuration file settings (installer.repos)
          backupTimestamp=$(date "+%Y%m%d%H%M%S")
          '' + concatMapStrings ( attrs :
                let repoType = getAttr attrs.type config.installer.repoTypes; 
                    target = escapeShellArg attrs.target; in
                ''
                  # ${attrs.type} repo ${target}
                  PATH=
                  for path in ${builtins.toString repoType.env}; do
                    PATH=$PATH:$path/bin:$path/sbin
                  done
                  if [ -d  ${target} ] && { cd ${target} && { ${ repoType.valid}; }; }; then
                      echo; echo '>>  ' updating ${attrs.type} repo ${target}
                      set -x; ${attrs.update}; set +x
                  else # [ make backup and ] initialize
                      [ -e ${target} ] && mv ${target} ${target}-$backupTimestamp
                      target=${target}
                      [ -d "$(dirname ${target})" ] || mkdir -p  "$(dirname ${target})"
                      echo; echo '>>  'initializing ${attrs.type} repo ${target}
                      set -x; ${attrs.initialize}; set +x
                  fi
                ''
              ) # flatten all repo definition to one list adding the repository
               ( concatLists  (flattenAttrs repos) )
      );
   };
}
