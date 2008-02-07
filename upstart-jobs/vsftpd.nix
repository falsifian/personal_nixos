{ vsftpd, anonymous_user }:

{
  name = "vsftpd";

  groups = [
    { name = "ftp";
      gid = (import ../system/ids.nix).gids.ftp;
    }
  ];
  
  users = [
    { name = "vsftpd";
      uid = (import ../system/ids.nix).uids.vsftpd;
      description = "VSFTPD user";
      home = "/homeless-shelter";
    }
  ] ++
  (if anonymous_user then [
    { name = "ftp";
      uid = (import ../system/ids.nix).uids.ftp;
      group = "ftp";
      description = "Anonymous ftp user";
      home = "/home/ftp";
    } 
  ]
  else
  []);
  
  job = "
description \"vsftpd server\"

start on network-interfaces/started
stop on network-interfaces/stop

start script
    cat > /etc/vsftpd.conf <<EOF
" + 
    (if anonymous_user then 
"anonymous_enable=YES"
    else
"anonymous_enable=NO") +
"
background=NO
listen=YES
nopriv_user=vsftpd
secure_chroot_dir=/var/ftp/empty
EOF

    mkdir -p /home/ftp &&
    chown -R ftp:ftp /home/ftp
end script

respawn ${vsftpd}/sbin/vsftpd /etc/vsftpd.conf
  ";
  
}
