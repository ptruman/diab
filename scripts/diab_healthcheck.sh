#!/bin/bash
# DIAB Healthcheck Script
#
HealthCheck=0
if [ -f $DIAB_HEALTHCHECK_SCRIPT ]; then
        /usr/sbin/diab_health_script.sh
        HealthCheck=$?
else
        /usr/sbin/diab_health_json.sh
        HealthCheck=$?
fi
exit $HealthCheck
