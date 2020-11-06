#!/bin/bash
if [ $DIAB_ENABLE_ADVANCED_LOGGING=1 ]; then
        advlog="-v"
else
        advlog=""
fi
/usr/sbin/diab_confbuild.sh
dnsdist -C /etc/dnsdist/dnsdist.conf --supervised $advlog
