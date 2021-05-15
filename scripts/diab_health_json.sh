#!/bin/bash
# DIAB Healthcheck JSON
#
# Script uses dnsdiab web API to parse actual running dnsdist output - which may differ from DIAB ENV settings
# Ascertain container IP
# ContainerIP=`tail -1 /etc/hosts | awk '{print $1}'`
ContainerIP=`hostname -i`
# Check if DIAB_WEB_APIKEY exists - if not, grab it from /etc/dnsdist/dnsdist.conf
if [ -f $DIAB_WEB_APIKEY ]; then
        DIAB_WEB_APIKEY=`cat /etc/dnsdist/dnsdist.conf | grep setWebserverConfig | awk '{print $2}' | sed 's/apiKey=//' | sed 's/\"//g'`
fi
DIAB_WEB_APIKEY=${DIAB_WEB_APIKEY::-1}
# Request the JSON server status
APIOutput=`curl -s -H "X-API-Key: $DIAB_WEB_APIKEY" http://$ContainerIP:8083/api/v1/servers/localhost`
# Count the servers
ServerCount=`echo $APIOutput | jq .servers | jq length`
# Set default health state (assume good)
HealthState=0
# Check every server and status
for (( i=0; i<$ServerCount; i++ ));
do
        ServerName=`echo $APIOutput | jq .servers[$i].name | sed 's/"//g'`
        ServerState=`echo $APIOutput | jq .servers[$i].state | sed 's/"//g'`
        # Force the returned status to uppercase and check if it's DOWN
        # (This is because up and UP have different meanings
        if [ ${ServerState^^} == "DOWN" ]; then
                HealthState=1
                if [ $DIAB_VERBOSEHEALTH ]; then
                        if [ $DIAB_VERBOSEHEALTH -eq 1 ]; then
                                echo "# DIAB : HEALTH  : ${ServerNames[$i]} reports ${UpStatuses[$i]}"
                        fi
                fi
        fi
done
