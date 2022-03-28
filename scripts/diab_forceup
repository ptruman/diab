#!/bin/bash
# DIAB Healthcheck JSON
#
# Script uses dnsdiab web API to parse actual running dnsdist output - which may differ from DIAB ENV settings
# Ascertain container IP
# ContainerIP=`tail -1 /etc/hosts | awk '{print $1}'`

ServerCount=`echo showServers\(\) | diab_cli SILENT | wc -l`
ServerCount=`expr $ServerCount - 2`
suffix=""
if [ $ServerCount > 1 ]; then
        suffix=s
fi
echo "# DIAB : INFO    : FORCE UP requested - attempted force start $ServerCount server$suffix"
for (( i=0; i<$ServerCount; i++ ));
do
        dispnum=`expr $i + 1`
        echo getServer\($i\):setUp\(\) | diab_cli
        echo getServer\($i\).upStatus=true | diab_cli
        dispname=`echo $DIAB_UPSTREAM_NAME | awk -F "," '{print $'$dispnum'}'`
        echo "# DIAB : INFO    : Attempted to force start server $dispnum ($dispname)"

done
