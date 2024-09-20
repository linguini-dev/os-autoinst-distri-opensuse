# SUSE's openQA tests
#
# Copyright 2020 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: Utilities for cloud-regionsrv-client testing
# Maintainer: Hristo Ilchev <hristo.ilchev@suse.com>

package publiccloud::cloud_registration;

use strict;
use warnings;
use testapi;
use utils;
use version_utils 'is_sle';

our @EXPORT = qw(
verify_packages
suseconnect_status
instance_is_registered
do_cleanup_instance
do_new_registration
do_forced_registration
);

sub verify_packages {
    # Required packages
    my $packages = "cloud-regionsrv-client";
    my $binary_path = is_sle('>15') && is_sle('<15-SP3') ? '/usr/sbin' : '';

    record_info('Check that all necessary binaries are available.');
    assert_script_run("${binary_path}/switchcloudguestservices");
    assert_script_run("${binary_path}/updatesmtcache");
    assert_script_run("${binary_path}/createregioninfo");
    assert_script_run("${binary_path}/suseconnect");
    assert_script_run("zypper se $packages");
    return 0;
}

sub suseconnect_status {
    # Check registration status and modules
    my $registered = false;
    if (script_run("suseconnect -s") == 0) {
        $registered = true;
    }

    record_info('suseconnect status', script_output("suseconnect -s"));
    return $registered;
}

sub is_instance_registered {
    my $status = @_;
    my $inverse_flag = "!";

    if ($status == true) { 
      my $inverse_flag = ""
      record_info('Registration-related data should be missing.');
    } else {
      record_info('Registration-related data should be available.');
    }

    # Zypper returns a non-0 code if there are no repositories
    assert_script_run("$inverse_flag zypper lr");

    assert_script_run("$inverse_flag grep REGISTRY_AUTH_FILE /etc/profile.local");
    assert_script_run("$inverse_flag grep DOCKER_CONFIG /etc/profile.local");
    assert_script_run("$inverse_flag grep susecloud /etc/docker/daemon.json");
    assert_script_run("$inverse_flag grep susecloud /etc/containers/registries.conf");
    assert_script_run("$inverse_flag grep susecloud /etc/hosts");
    assert_script_run("$inverse_flag ls -A /etc/zypp/credentials.d)");
    assert_script_run("$inverse_flag ls -A /etc/zypp/services.d)");
    assert_script_run("$inverse_flag ls -A /var/cache/cloudregister)");
    return 0;
}

sub do_cleanup_instance {
    record_info('Check for existing registration data.');
    is_instance_registered(true);
    record_info("Clean the instance of any data related registration.", script_output('registercloudguest --clean'));
    assert_script_run("registercloudguest --clean");

    record_info('Check if instance is clean.');
    is_instance_registered(false);
    return 0;
}

sub do_new_registration {
    record_info('Starting registration...');
    assert_script_run("registercloudguest");
    is_instance_registered(true);

    record_info('Testing docker.');
    assert_script_run("source /etc/profile.local");
    assert_script_run("systemctl start docker.service");
    record_info("systemctl status docker.service", script_output("systemctl status docker.service"));
    assert_script_run("docker pull bci/bci-base");
    assert_script_run("systemctl stop docker.service");
  
    record_info('Testing podman.');
    assert_script_run("zypper install podman");
    assert_script_run("podman pull bci/bci-base");
    do_cleanup_instance();
    return 0;
}

sub do_forced_registration {
    record_info('Run registercloudguest.');
    assert_script_run("registercloudguest");
    
    record_info('Start a forced registration with `registercloudguest --force-new`');
    assert_script_run("registercloudguest --force-new");
    is_instance_registered(true);

    record_info('Remove registration server certificates.');
    assert_script_run("rm /etc/pki/trust/anchors/registration_server_*.pem");
    assert_script_run("update-ca-certificates");

    record_info('Start a forced registration with `registercloudguest --force-new`');
    assert_script_run("registercloudguest --force-new");
    is_instance_registered(true);

    record_info('Update failover server');
    assert_script_run("ip=`grep -m 1 susecloud.net /etc/hosts | cut -f1` && iptables -A OUTPUT -d $ip -j DROP");
    assert_script_run("zypper ref");

    # I have no idea what this should output, so YOLO until I test it out 🤷
    assert_script_run("A=$(grep -i equivalent /var/log/cloudregister) && B=$(grep susecloud.net /etc/hosts) && if [[ \$A==\$B ]]");
    return 0;
}

sub check_instance_registered {
    my ($instance) = @_;
    if ($instance->ssh_script_output(cmd => 'LANG=C zypper -t lr | awk "/^\s?[[:digit:]]+/{c++} END {print c}"', timeout => 300) == 0) {
        record_info('zypper lr', $instance->ssh_script_output(cmd => 'zypper -t lr ||:'));
        die('The list of zypper repositories is empty.');
    }
    if ($instance->ssh_script_output(cmd => 'sudo ls /etc/zypp/credentials.d/ | wc -l') == 0) {
        die('Directory /etc/zypp/credentials.d/ is empty.');
    }
}

sub check_instance_unregistered {
    my ($instance, $error) = @_;
    if ($instance->ssh_script_output(cmd => 'sudo ls /etc/zypp/credentials.d/ | wc -l') != 0) {
        my $creds_output = $instance->ssh_script_output(cmd => 'sudo ls -la /etc/zypp/credentials.d/');
        die("/etc/zypp/credentials.d/ is not empty:\n" . $creds_output);
    }
    my $out = $instance->ssh_script_output(cmd => 'zypper -t lr ||:', timeout => 300);
    return if ($out =~ /No repositories defined/m);

    for (split('\n', $out)) {
        if ($_ =~ /^\s?\d+/ && $_ !~ /SUSE_Maintenance/) {
            record_info('zypper lr', $out);
            die($error);
        }
    }
}

1;