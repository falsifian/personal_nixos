{pkgs, config, ...}:

with pkgs.lib;

let

  ids = config.ids;
  users = config.users;

  userOpts = {name, config, ...}:

  {
    options = {
      name = mkOption {
        type = with types; uniq string;
        description = "The name of the user account. If undefined, the name of the attribute set will be used.";
      };
      description = mkOption {
        type = with types; uniq string;
        default = "";
        description = "A short description of the user account.";
      };
      uid = mkOption {
        type = with types; uniq (nullOr int);
        default = null;
        description = "The account UID. If undefined, NixOS will select a UID.";
      };
      group = mkOption {
        type = with types; uniq string;
        default = "nogroup";
        description = "The user's primary group.";
      };
      extraGroups = mkOption {
        type = types.listOf types.string;
        default = [];
        description = "The user's auxiliary groups.";
      };
      home = mkOption {
        type = with types; uniq string;
        default = "/var/empty";
        description = "The user's home directory.";
      };
      shell = mkOption {
        type = with types; uniq string;
        default = "/noshell";
        description = "The path to the user's shell.";
      };
      createHome = mkOption {
        type = types.bool;
        default = false;
        description = "If true, the home directory will be created automatically.";
      };
      useDefaultShell = mkOption {
        type = types.bool;
        default = false;
        description = "If true, the user's shell will be set to <literal>users.defaultUserShell</literal>.";
      };
      password = mkOption {
        type = with types; uniq (nullOr string);
        default = null;
        description = "The user's password. If undefined, no password is set for the user.  Warning: do not set confidential information here because this data would be readable by all.  This option should only be used for public account such as guest.";
      };
      isSystemUser = mkOption {
        type = types.bool;
        default = true;
        description = "Indicates if the user is a system user or not.";
      };
      createUser = mkOption {
        type = types.bool;
        default = true;
        description = "
          Indicates if the user should be created automatically as a local user.
          Set this to false if the user for instance is an LDAP user. NixOS will
          then not modify any of the basic properties for the user account.
        ";
      };
    };

    config = {
      name = mkDefault name;
      uid = mkDefault (attrByPath [name] null ids.uids);
      shell = mkIf config.useDefaultShell (mkDefault users.defaultUserShell);
    };
  };

  # Groups to be created/updated by NixOS.
  groups =
    let
      defaultGroups =
        [ { name = "root";
            gid = ids.gids.root;
          }
          { name = "wheel";
            gid = ids.gids.wheel;
          }
          { name = "disk";
            gid = ids.gids.disk;
          }
          { name = "kmem";
            gid = ids.gids.kmem;
          }
          { name = "tty";
            gid = ids.gids.tty;
          }
          { name = "floppy";
            gid = ids.gids.floppy;
          }
          { name = "uucp";
            gid = ids.gids.uucp;
          }
          { name = "lp";
            gid = ids.gids.lp;
          }
          { name = "cdrom";
            gid = ids.gids.cdrom;
          }
          { name = "tape";
            gid = ids.gids.tape;
          }
          { name = "audio";
            gid = ids.gids.audio;
          }
          { name = "video";
            gid = ids.gids.video;
          }
          { name = "dialout";
            gid = ids.gids.dialout;
          }
          { name = "nogroup";
            gid = ids.gids.nogroup;
          }
          { name = "users";
            gid = ids.gids.users;
          }
          { name = "nixbld";
            gid = ids.gids.nixbld;
          }
          { name = "utmp";
            gid = ids.gids.utmp;
          }
        ];

      addAttrs =
        { name, gid ? "" }:
        { inherit name gid; };

    in map addAttrs (defaultGroups ++ config.users.extraGroups);


  # Note: the 'X' in front of the password is to distinguish between
  # having an empty password, and not having a password.
  serializedUser = userName: let u = getAttr userName config.users.extraUsers; in "${u.name}\n${u.description}\n${if u.uid != null then toString u.uid else ""}\n${u.group}\n${toString (concatStringsSep "," u.extraGroups)}\n${u.home}\n${u.shell}\n${toString u.createHome}\n${if u.password != null then "X" + u.password else ""}\n${toString u.isSystemUser}\n${if u.createUser then "yes" else "no"}\n";

  serializedGroup = g: "${g.name}\n${toString g.gid}";

  # keep this extra file so that cat can be used to pass special chars such as "`" which is used in the avahi daemon
  usersFile = pkgs.writeText "users" (
    concatMapStrings serializedUser (attrNames config.users.extraUsers)
  );

in

{

  ###### interface

  options = {

    users.extraUsers = mkOption {
      default = {};
      type = types.loaOf types.optionSet;
      example = {
        alice = {
          uid = 1234;
          description = "Alice";
          home = "/home/alice";
          createHome = true;
          group = "users";
          extraGroups = ["wheel"];
          shell = "/bin/sh";
          password = "foobar";
        };
      };
      description = ''
        Additional user accounts to be created automatically by the system.
      '';
      options = [ userOpts ];
    };

    users.extraGroups = mkOption {
      default = [];
      example =
        [ { name = "students";
            gid = 1001;
          }
        ];
      description = ''
        Additional groups to be created automatically by the system.
      '';
    };

    user = mkOption {
      default = {};
      description = ''
        This option defines settings for individual users on the system.
      '';
      type = types.loaOf types.optionSet;
      options = [ ];
    };

  };


  ###### implementation

  config = {

    users.extraUsers = {
      root = {
        description = "System administrator";
        home = "/root";
        shell = config.users.defaultUserShell;
        group = "root";
      };
      nobody = {
        description = "Unprivileged account (don't use!)";
      };
    };

    system.activationScripts.rootPasswd = stringAfter [ "etc" ]
      ''
        # If there is no password file yet, create a root account with an
        # empty password.
        if ! test -e /etc/passwd; then
            rootHome=/root
            touch /etc/passwd; chmod 0644 /etc/passwd
            touch /etc/group; chmod 0644 /etc/group
            touch /etc/shadow; chmod 0600 /etc/shadow
            # Can't use useradd, since it complains that it doesn't know us
            # (bootstrap problem!).
            echo "root:x:0:0:System administrator:$rootHome:${config.users.defaultUserShell}" >> /etc/passwd
            echo "root::::::::" >> /etc/shadow
        fi
      '';

    system.activationScripts.users = stringAfter [ "groups" ]
      ''
        echo "updating users..."

        cat ${usersFile} | while true; do
            read name || break
            read description
            read uid
            read group
            read extraGroups
            read home
            read shell
            read createHome
            read password
            read isSystemUser
            read createUser

            if ! test "$createUser" = "yes"; then
                continue
            fi

            if ! curEnt=$(getent passwd "$name"); then
                useradd ''${isSystemUser:+--system} \
                    --comment "$description" \
                    ''${uid:+--uid $uid} \
                    --gid "$group" \
                    --groups "$extraGroups" \
                    --home "$home" \
                    --shell "$shell" \
                    ''${createHome:+--create-home} \
                    "$name"
                if test "''${password:0:1}" = 'X'; then
                    (echo "''${password:1}"; echo "''${password:1}") | ${pkgs.shadow}/bin/passwd "$name"
                fi
            else
                #echo "updating user $name..."
                oldIFS="$IFS"; IFS=:; set -- $curEnt; IFS="$oldIFS"
                prevUid=$3
                prevHome=$6
                # Don't change the UID if it's the same, otherwise usermod
                # will complain.
                if test "$prevUid" = "$uid"; then unset uid; fi
                # Don't change the home directory if it's the same to prevent
                # unnecessary warnings about logged in users.
                if test "$prevHome" = "$home"; then unset home; fi
                usermod \
                    --comment "$description" \
                    ''${uid:+--uid $uid} \
                    --gid "$group" \
                    --groups "$extraGroups" \
                    ''${home:+--home "$home"} \
                    --shell "$shell" \
                    "$name"
            fi

        done
      '';

    system.activationScripts.groups = stringAfter [ "rootPasswd" "binsh" "etc" "var" ]
      ''
        echo "updating groups..."

        while true; do
            read name || break
            read gid

            if ! curEnt=$(getent group "$name"); then
                groupadd --system \
                    ''${gid:+--gid $gid} \
                    "$name"
            else
                #echo "updating group $name..."
                oldIFS="$IFS"; IFS=:; set -- $curEnt; IFS="$oldIFS"
                prevGid=$3
                if test -n "$gid" -a "$prevGid" != "$gid"; then
                    groupmod --gid $gid "$name"
                fi
            fi
        done <<EndOfGroupList
        ${concatStringsSep "\n" (map serializedGroup groups)}
        EndOfGroupList
      '';

  };

}
