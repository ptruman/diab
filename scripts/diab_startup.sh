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
# Check if we should start routedns, or just dnsdist...
if [ `ls /etc/routedns | wc -l` -eq 0 ]; then
        # No files - start dnsdist only...
        dnsdist -C /etc/dnsdist/dnsdist.conf --supervised $advlog
else
        # Files found - start dnsdist (background) and routedns
        dnsdist -C /etc/dnsdist/dnsdist.conf --supervised $advlog &
        routedns /etc/routedns/*.toml
fi

