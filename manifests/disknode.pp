#
#class based on the dpm wiki example
#
class dpm::disknode (
  $configure_vos =  $dpm::params::configure_vos,
  $configure_gridmap =  $dpm::params::configure_gridmap,

  #cluster options
  $headnode_fqdn =  $dpm::params::headnode_fqdn,
  $disk_nodes =  $dpm::params::disk_nodes,
  $localdomain =  $dpm::params::localdomain,
  $webdav_enabled = $dpm::params::webdav_enabled,

  #dpmmgr user options
  $dpmmgr_uid =  $dpm::params::dpmmgr_uid,
  $dpmmgr_user =  $dpm::params::dpmmgr_user,

  #DB/Auth options
  $db_user =  $dpm::params::db_user,
  $db_pass =  $dpm::params::db_pass,
  $mysql_root_pass =  $dpm::params::mysql_root_pass,
  $token_password =  $dpm::params::token_password,
  $xrootd_sharedkey =  $dpm::params::xrootd_sharedkey,
  $xrootd_use_voms =  $dpm::params::xrootd_use_voms,
  
  #VOs parameters
  $volist =  $dpm::params::volist,
  $groupmap =  $dpm::params::groupmap,
  
  #Debug Flag
  $debug = $dpm::params::debug,

  #GridFTP redirection
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
    
    
    Class[Lcgdm::Base::Install] -> Class[Lcgdm::Rfio::Install]
    if($webdav_enabled){
      Class[Dmlite::Plugins::Adapter::Install] ~> Class[Dmlite::Dav::Service]
    }
    Class[Dmlite::Plugins::Adapter::Install] ~> Class[Dmlite::Gridftp]

    # lcgdm configuration.
    #
    class{"lcgdm::base":
      uid     => $dpmmgr_uid,
    }
   
    
    class{"lcgdm::ns::client":
      flavor  => "dpns",
      dpmhost => "${headnode_fqdn}"
    }

    #
    # RFIO configuration.
    #
    class{"lcgdm::rfio":
      dpmhost => $headnode_fqdn,
    }
    
    #
    # Entries in the shift.conf file, you can add in 'host' below the list of
    # machines that the DPM should trust (if any).
    #
    lcgdm::shift::trust_value{
      "DPM TRUST":
        component => "DPM",
        host      => "${headnode_fqdn} ${disk_nodes_str}";
      "DPNS TRUST":
        component => "DPNS",
        host      => "${headnode_fqdn} ${disk_nodes_str}";
      "RFIO TRUST":
        component => "RFIOD",
        host      => "${headnode_fqdn} ${disk_nodes_str}",
        all       => true
    }
    lcgdm::shift::protocol{"PROTOCOLS":
      component => "DPM",
      proto     => "rfio gsiftp http https xroot"
    }

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
    # dmlite plugin configuration.
    class{"dmlite::disk":
      token_password => "${token_password}",
      dpmhost        => "${headnode_fqdn}",
      nshost         => "${headnode_fqdn}",
      mysql_username => "${db_user}",
      mysql_password => "${db_pass}",
      mysql_host     => "${headnode_fqdn}",
      enable_space_reporting => $enable_space_reporting,
    }
    
    #
    # dmlite frontend configuration.
    #
    if($webdav_enabled){
      class{"dmlite::dav":}
    }
    

    class{"dmlite::gridftp":
      dpmhost => "${headnode_fqdn}",
      data_node => $gridftp_redirect,
    }

    
    # The XrootD configuration is a bit more complicated and
    # the full config (incl. federations) will be explained here:
    # https://svnweb.cern.ch/trac/lcgdm/wiki/Dpm/Xroot/PuppetSetup
    
    #
    # The simplest xrootd configuration.
    #
    class{"xrootd::config":
      xrootd_user  => $dpmmgr_user,
      xrootd_group => $dpmmgr_user
    }
    
    class{"dmlite::xrootd":
      nodetype              => [ 'disk' ],
      domain                => "${localdomain}",
      dpm_xrootd_debug      => $debug,
      dpm_xrootd_sharedkey  => "${xrootd_sharedkey}",
      xrootd_use_voms => true,
      xrd_report => $xrd_report,
      xrootd_monitor => $xrootd_monitor,
      site_name => $site_name 
    }
    
  }
                                                                                                    
