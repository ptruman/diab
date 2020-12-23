#!/bin/bash
# DIAB Startup Script
# Set Version
#
# Check for/enable advanced logging
if [ $DIAB_ENABLE_ADVANCED_LOGGING ]; then
        if [ $DIAB_ENABLE_ADVANCED_LOGGING -eq 1 ]; then
                advlog="-v"
        else
                advlog=""
        fi
fi
# Run the configurator....
/usr/sbin/diab_confbuild.sh
# Start dnsdist in the background
dnsdist -C /etc/dnsdist/dnsdist.conf --supervised $advlog &
# Start routedns
routedns /etc/routedns/*.toml
