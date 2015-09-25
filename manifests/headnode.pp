#
#class based on the dpm wiki example
#
class dpm::headnode (
    $configure_vos =  $dpm::params::configure_vos,
    $configure_gridmap =  $dpm::params::configure_gridmap,

    #cluster options
    $headnode_fqdn =  $dpm::params::headnode_fqdn,
    $disk_nodes =  $dpm::params::disk_nodes,
    $localdomain =  $dpm::params::localdomain,
    $webdav_enabled = $dpm::params::webdav_enabled,
    $memcached_enabled = $dpm::params::memcached_enabled,

    #dpmmgr user options
    $dpmmgr_uid =  $dpm::params::dpmmgr_uid,
    $dpmmgr_user =  $dpm::params::dpmmgr_user,

    #DB/Auth options
    $db_user =  $dpm::params::db_user,
    $db_pass =  $dpm::params::db_pass,
    #$db_hash =  "*3573F3D4D433A1EAB3058322CA680B0FE2F3E9D8",
    $db_hash =  $dpm::params::db_hash,
    $mysql_root_pass =  $dpm::params::mysql_root_pass,
    $token_password =  $dpm::params::token_password,
    $xrootd_sharedkey =  $dpm::params::xrootd_sharedkey,
    $xrootd_use_voms =  $dpm::params::xrootd_use_voms,

    #VOs parameters
    $volist =  $dpm::params::volist,
    $groupmap =  $dpm::params::groupmap,

    #Debug Flag
    $debug = $dpm::params::debug,

    #XRootd federations
    $dpm_xrootd_fedredirs = $dpm::params::dpm_xrootd_fedredirs,

    #GridFtp redirection
    $gridftp_redirect = $dpm::params::gridftp_redirect,

    #Enable Space reporting
    $enable_space_reporting =  $dpm::params::enable_space_reporting,
  
  )inherits dpm::params {

   #XRootd monitoring parameters
    if($dpm::params::xrd_report){
      $xrd_report = $dpm::params::xrd_report
    }else{
      $xrd_report  = undef
    }

    if($dpm::params::xrootd_monitor){
        $xrootd_monitor = $dpm::params::xrootd_monitor
    }else{
      $xrootd_monitor = undef
    }
    
    if($dpm::params::site_name){
        $site_name = $dpm::params::site_name
    }else{
      $site_name = undef
    }

    $disk_nodes_str=join($disk_nodes,' ');
    
    #some packages that should be present if we want things to run
    ensure_resource('package',['openssh-server','openssh-clients','vim-minimal','cronie','policycoreutils','selinux-policy'],{ensure => present,before => Class[Lcgdm::Base::Config]})

    #
    # Set inter-module dependencies
    #
    Class[Mysql::Server] -> Class[Lcgdm::Ns::Service]

    Class[Lcgdm::Dpm::Service] -> Class[Dmlite::Plugins::Adapter::Install]
    Class[Dmlite::Plugins::Adapter::Install] ~> Class[Dmlite::Srm]
    Class[Dmlite::Plugins::Adapter::Install] ~> Class[Dmlite::Gridftp]
    Class[Dmlite::Plugins::Mysql::Install] ~> Class[Dmlite::Srm]
    Class[Dmlite::Plugins::Mysql::Install] ~> Class[Dmlite::Gridftp]

    if($webdav_enabled){
      Class[Dmlite::Plugins::Adapter::Install] ~> Class[Dmlite::Dav]
      Class[Dmlite::Plugins::Mysql::Install] ~> Class[Dmlite::Dav]
    }

    if($memcached_enabled){
       Class[Dmlite::Plugins::Memcache::Install] ~> Class[Dmlite::Dav::Service]
       Class[Dmlite::Plugins::Memcache::Install] ~> Class[Dmlite::Gridftp]
       Class[Dmlite::Plugins::Memcache::Install] ~> Class[Dmlite::Srm]
    }


    #
    # MySQL server setup - disable if it is not local
    #

    $override_options = {
      'mysqld' => {
            'max_connections'    => '1000',
            'query_cache_size'   => '256M',
            'query_cache_limit'  => '1MB',
            'innodb_flush_method' => 'O_DIRECT',
            'innodb_buffer_pool_size' => '1000000000',
            'bind-address' => '0.0.0.0',
          }
    }

    
    class{"mysql::server":
      service_enabled => true,
      root_password   => "${mysql_root_pass}",
      override_options => $override_options  
    }


    #configure grants
    ensure_resource('mysql_user', $disk_nodes.map |$node| {"${db_user}@$node"},{
      ensure        => present,
      password_hash => $db_hash,
      provider      => 'mysql',
      tag => 'nodeuser',
    })


    
  
    create_resources(
      'mysql_grant',
      $disk_nodes.reduce({}) |$memo, $node| {
         $temp=merge($memo,
           {
             "${db_user}@$node/cns_db.*" => {
               user => "${db_user}@$node",
               require => [ Mysql_database['cns_db'], Mysql_user["${db_user}@$node"] ]
             }            
           }
         )
         $temp
      },
    
      {
        ensure     => 'present',
        options    => ['GRANT'],
        privileges => ['ALL'],
        table      => 'cns_db.*',
        provider   => 'mysql',
   })
    
    class{"lcgdm::base":
      uid     => $dpmmgr_uid,
    }


    #
    # DPM and DPNS daemon configuration.
    #
    class{"lcgdm":
      dbflavor => "mysql",
      dbuser   => "${db_user}",
      dbpass   => "${db_pass}",
      dbhost   => "localhost",
      domain   => "${localdomain}",
      volist   => $volist,
    }

    #
    # RFIO configuration.
    #
    class{"lcgdm::rfio":
      dpmhost => "${::fqdn}",
    }

    #
    # Entries in the shift.conf file, you can add in 'host' below the list of
    # machines that the DPM should trust (if any).
    #
    lcgdm::shift::trust_value{
      "DPM TRUST":
        component => "DPM",
        host      => $disk_nodes_str;
      "DPNS TRUST":
        component => "DPNS",
        host      => $disk_nodes_str;
      "RFIO TRUST":
        component => "RFIOD",
        host      => $disk_nodes_str,
        all       => true
    }

    lcgdm::shift::protocol{"PROTOCOLS":
      component => "DPM",
      proto     => "rfio gsiftp http https xroot"
    }


    #
    # VOMS configuration (same VOs as above): implements all the voms classes in the vo list
    #
    #WARN!!!!: in 3.4 collect has been renamed "map"
    if($configure_vos){
      class{ $volist.map |$vo| {"voms::$vo"}:}
      #Create the users: no pool accounts just one user per group
      ensure_resource('user', values($groupmap), {ensure => present})
    }


    if($configure_gridmap){
      #setup the gridmap file
      lcgdm::mkgridmap::file {"lcgdm-mkgridmap":
        configfile   => "/etc/lcgdm-mkgridmap.conf",
        localmapfile => "/etc/lcgdm-mapfile-local",
        logfile      => "/var/log/lcgdm-mkgridmap.log",
        groupmap     => $groupmap,
        localmap     => {"nobody" => "nogroup"}
      }
    }

    #
    # dmlite configuration.
    #
    class{"dmlite::head":
      token_password => "${token_password}",
      mysql_username => "${db_user}",
      mysql_password => "${db_pass}",
      enable_space_reporting => $enable_space_reporting,
    }

    #
    # Frontends based on dmlite.
    #
    if($webdav_enabled){
      class{"dmlite::dav":}
    }
    class{"dmlite::srm":}
    class{"dmlite::gridftp":
      dpmhost => "${::fqdn}",
      remote_nodes => $gridftp_redirect ? {
        1 => regsubst(regsubst("${disk_nodes_str} ","(\S)\s","\1:2811 ",'G'),"(\S)\s+(\S)","\1,\2",'G'),
        0 => undef,
      },                   
    }

    if($gridftp_redirect == 1){
      lcgdm::shift::protocol_head{"GRIDFTP":
             component => "DPM",
             protohead => "FTPHEAD",
             host      => "${::fqdn}",
      }  
    }

    # The XrootD configuration is a bit more complicated and
    # the full config (incl. federations) will be explained here:
    # https://svnweb.cern.ch/trac/lcgdm/wiki/Dpm/Xroot/PuppetSetup

    #
    # The simplest xrootd configuration.
    #
    class{"xrootd::config":
      xrootd_user  => $dpmmgr_user,
      xrootd_group => $dpmmgr_user,
    }

    class{"dmlite::xrootd":
          nodetype              => [ 'head' ],
          domain                => "${localdomain}",
          dpm_xrootd_debug      => $debug,
          dpm_xrootd_sharedkey  => "${xrootd_sharedkey}",
          xrootd_use_voms       => $xrootd_use_voms,
          dpm_xrootd_fedredirs => $dpm_xrootd_fedredirs,
          xrd_report => $xrd_report,
          xrootd_monitor => $xrootd_monitor,
          site_name => $site_name
   }

   if($memcached_enabled)
   {
     class{"memcached":
       max_memory => 512,
       listen_ip => '127.0.0.1',
     }
     ->
     class{"dmlite::plugins::memcache":
       expiration_limit => 600,
       posix            => 'on',
       func_counter     => 'on',
     }
   }



}
