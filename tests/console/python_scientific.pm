# SUSE's openQA tests
#
# Copyright 2021 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: Scientific python packages
# * Test numpy
# * Test scipy
# Maintainer: Felix Niederwanger <felix.niederwanger@suse.de>

use base 'consoletest';
use strict;
use warnings;
use testapi;
use serial_terminal 'select_serial_terminal';
use utils;
use version_utils qw(is_sle is_tumbleweed);
use registration 'is_phub_ready';

sub run_python_script {
    my $script = shift;
    my $logfile = "output.txt";
    record_info($script, "Running python script: $script");
    assert_script_run("curl " . data_url("python/$script") . " -o '$script'");
    assert_script_run("chmod a+rx '$script'");
    assert_script_run("./$script 2>&1 | tee $logfile");
    if (script_run("grep 'Softfail' $logfile") == 0) {
        # Except for Tumbleweed, scipy is still outdated and bsc#1180605 is therefore triggered
        if ((script_run("grep 'Softfail' $logfile | grep 'bsc#1180605'") == 0) && (!is_tumbleweed)) {
            record_info("scipy-fft", "scipy-fft module not available", result => 'softfail');
        } else {
            my $failmsg = script_output("grep 'Softfail' '$logfile'");
            record_info('Softfail', "$failmsg", result => 'softfail');
        }
    }
}

sub run {
    select_serial_terminal;

    # Package 'python3-scipy' requires PackageHub is available
    return unless is_phub_ready();

    my $scipy = is_sle('<15-sp1') || is_sle('>=16.0') ? '' : 'python3-scipy';
    zypper_call "in python3 python3-numpy $scipy";
    # Run python scripts
    run_python_script('python3-numpy-test.py');
    run_python_script('python3-scipy-test.py') unless is_sle('<15-sp1');
}

sub post_fail_hook {
    my $self = shift;
    $self->cleanup();
    $self->SUPER::post_fail_hook;
}

sub post_run_hook {
    my $self = shift;
    $self->cleanup();
    $self->SUPER::post_run_hook;
}

sub cleanup {
    script_run('rm -f python3-numpy-test.py python3-scipy-test.py');
}

1;
