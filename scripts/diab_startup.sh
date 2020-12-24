#!/bin/bash
# DIAB Startup Script
echo "#"
echo "# DIAB : INFO    : Attempting to start diab..."
# Run the configurator....
echo "# DIAB : INFO    : Launching diab configurator..."
/usr/sbin/diab_confbuild.sh
# Check for/enable advanced logging
if [ $DIAB_ENABLE_ADVANCED_LOGGING ]; then
        if [ $DIAB_ENABLE_ADVANCED_LOGGING -eq 1 ]; then
                echo "# DIAB : INFO    : Advanced logging requested..."
                advlog="-v"
        else
                advlog=""
        fi
fi
# Check if we should start routedns, or just dnsdist...
if [ `ls /etc/routedns | wc -l` -eq 0 ]; then
        # No files - start dnsdist only...
        echo "# DIAB : INFO    : Launching dnsdist..."
        dnsdist -C /etc/dnsdist/dnsdist.conf --supervised $advlog
else
        # Files found - start dnsdist (background) and routedns
        echo "# DIAB : INFO    : Launching dnsdist and routedns..."
        dnsdist -C /etc/dnsdist/dnsdist.conf --supervised $advlog &
        routedns /etc/routedns/*.toml
fi
