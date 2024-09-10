# SUSE's openQA tests
#
# Copyright 2019-2024 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Package: python3-ec2metadata iproute2 ca-certificates
# Summary: This is just bunch of random commands overviewing the public cloud instance
# We just register the system, install random package, see the system and network configuration
# This test module will fail at the end to prove that the test run will continue without rollback
#
# Maintainer: qa-c <qa-c@suse.de>

use base 'publiccloud::basetest';
use registration;
use warnings;
use testapi;
use strict;
use utils;
use publiccloud::utils;
use version_utils qw(is_sle is_sle_micro);
use Utils::Logging 'tar_and_upload_log';


sub initial_boot {
    # Required packages
    my @packages = qw(cloud-regionsrv-client);
    
    # Check if binaries are available and work as expected
    assert_script_run("/usr/sbin/switchcloudguestservices");
    assert_script_run("/usr/sbin/updatesmtcache");
    assert_script_run("/usr/sbin/createregioninfo");

    assert_script_run("zypper lr");

    # Check registration status and modules
    assert_script_run("suseconnect -s");
    assert_script_run("suseconnect -l");

}

sub check_configuration {
    my $is_clean = shift;
    if ($is_clean == "yes") { 
      my $inverse_flag = ""
    } else { 
      my $inverse_flag = "!"
    }

    assert_script_run("$inverse_flag zypper lr");
    assert_script_run("$inverse_flag grep REGISTRY_AUTH_FILE /etc/profile.local");
    assert_script_run("$inverse_flag grep DOCKER_CONFIG /etc/profile.local");
    assert_script_run("$inverse_flag grep susecloud /etc/docker/daemon.json");
    assert_script_run("$inverse_flag grep susecloud /etc/containers/registries.conf");
    assert_script_run("$inverse_flag grep susecloud /etc/hosts");
}

sub clean_run {
    check_configuration("yes");

    assert_script_run("registercloudguest --clean");

    assert_script_run("! ls -A /etc/zypp/credentials.d)");
    assert_script_run("! ls -A /etc/zypp/services.d)");
    assert_script_run("! ls -A /var/cache/cloudregister)");
     
    check_configuration("no");
}

sub new_registration {
    # Start a new registration
    assert_script_run("registercloudguest");
    check_configuration("yes");

    # Test Docker runtime
    assert_script_run("source /etc/profile.local");
    assert_script_run("systemctl start docker.service");
    assert_script_run("systemctl status docker.service");
    assert_script_run("docker pull bci/bci-base");
    assert_script_run("systemctl stop docker.service");
  
    # Test Podman runtime
    assert_script_run("zypper install podman");
    assert_script_run("podman pull bci/bci-base");
    clean_run();
}

sub new_registration_force {
    assert_script_run("registercloudguest");
    assert_script_run("registercloudguest --force-new");
    check_configuration("yes");

    assert_script_run("rm /etc/pki/trust/anchors/registration_server_*.pem");
    assert_script_run("update-ca-certificates");
    assert_script_run("registercloudguest --force-new");
    check_configuration("yes");

    #Update server failover
    assert_script_run("ip=`grep -m 1 susecloud.net /etc/hosts | cut -f1`");
    assert_script_run("iptables -A OUTPUT -d $ip -j DROP");
    assert_script_run("zypper ref");
    assert_script_run("grep -i equivalent /var/log/cloudregister");
    assert_script_run("grep susecloud.net /etc/hosts");
    assert_script_run("IP addresses in the last two outputs should match");
}

sub sap {
  #soon

}

sub migration {
  #soon
}

sub extended_testing {
  #soon
}

sub run {
    my ($self, $args) = @_;
    initial_boot();
    clean_run();
    new_registration();
    new_registration_force();
}


1;
