#!/bin/bash
# DIAB Healthcheck Script
#
# Script uses diab_cli to parse actual running dnsdist output - which may differ from DIAB ENV settings
# Get base output (including states) via diab_cli and count the lines
ShowServerOutput=`echo showServers\(\) | diab_cli`
ShowServerLines=`echo "$ShowServerOutput" | wc -l`
# Set the head and tail params
ServerCount=`expr $ShowServerLines - 3`
Ceiling=`expr $ShowServerLines - 1`
# Extract the server lines only
DiabCLIOutput=`echo "$ShowServerOutput" | head -$Ceiling | tail -$ServerCount`
# Grab servernames and statuses
ServerNamesString=`echo "$DiabCLIOutput" | awk '{print $2}'`
ServerNamesString=`echo $ServerNamesString | sed "s/ /,/g"`
UpStatusesString=`echo "$DiabCLIOutput" | awk '{print $4}'`
UpStatusesString=`echo $UpStatusesString | sed "s/ /,/g"`
# Convert servernames and statuses to arrays
IFS=',' read -ra ServerNames <<< "$ServerNamesString"
IFS=',' read -ra UpStatuses <<< "$UpStatusesString"
# Set default healthstate (assume good)
HealthState=0
# Check every server and status
for (( i=0; i<$ServerCount; i++ ));
do
        # Force the returned status to uppercase and check if it's DOWN
        # (This is because up and UP have different meanings
        if [ ${UpStatuses[$i]^^} == "DOWN" ]; then
                HealthState=1
                if [ $DIAB_VERBOSEHEALTH ]; then
                        if [ $DIAB_VERBOSEHEALTH -eq 1 ]; then
                                echo "# DIAB : HEALTH  : ${ServerNames[$i]} reports ${UpStatuses[$i]}"
                        fi
                fi
        fi
done
exit $HealthState
