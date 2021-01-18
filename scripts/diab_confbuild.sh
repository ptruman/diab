#!/bin/bash
# DIAB Configuration Build Script
# Set Version
DV="1.8"
echo "# DIAB : INFO    : diab V$DV configurator starting..."
# Check for existing config file...
if [ -f "/etc/dnsdist/dnsdist.conf" ]; then
        # Config present - do nothing
        echo "# DIAB : INFO    : Found existing /etc/dnsdist/dnsdist.conf - skipping config build"
        echo "# DIAB : WARNING : If you have changed Docker environment variables, they will not take effect as the existing file will be used."
else
        # Check for IPv6 
        if [ $DIAB_ENABLE_IPV6 ]; then
                if [ $DIAB_ENABLE_IPV6 -eq 1 ]; then
                        IPV6=1
                fi
        fi
        # Get container IP
        ContainerIP=`awk 'END{print $1}' /etc/hosts`
        # Test for key variables
        # DIAB_UPSTREAM_IP_AND_PORT is a basic requirement - no upstream server = no operation.
        if [ -f $DIAB_UPSTREAM_IP_AND_PORT ]; then
                echo "# DIAB : FAILURE : Docker Environment DIAB_UPSTREAM_IP_AND_PORT is NOT set.  Cannot continue. Exiting."
                exit 0;
        fi
        # DIAB_TRUSTED_LANS is a basic requirement
        if [ -f $DIAB_TRUSTED_LANS ]; then
                echo "# DIAB : FAILURE : Docker Environment DIAB_TRUSTED_LANS is NOT set.  Cannot continue. Exiting."
                exit 0;
        fi
        # No DIAB_UPSTREAM_NAME is not critical but needed in the webserver - so if not provided, we use the IP/PORT
        if [ -f $DIAB_UPSTREAM_NAME ]; then
                export DIAB_UPSTREAM_NAME=$DIAB_UPSTREAM_IP_AND_PORT
                echo "# DIAB : WARNING : DIAB_UPSTREAM_NAME was not set. Using $DIAB_UPSTREAM_IP_AND_PORT"
        fi
        echo "# DIAB : INFO    : Next DNS hops requested as $DIAB_UPSTREAM_NAME ($DIAB_UPSTREAM_IP_AND_PORT)"
        # Create the config folders if not present...
        mkdir -p /etc/dnsdist
        mkdir -p /etc/routedns
        if [ -f "/etc/routedns/listeners.toml" ]; then
                echo "# DIAB : INFO    : Found existing /etc/routedns/listeners.toml - skipping blank creation"
                CreateRouteDNSListeners=0
        else
                echo "# DIAB : INFO    : No existing /etc/routedns/listeners.toml found - creating shell"
                CreateRouteDNSListeners=1
                echo > /etc/routedns/listeners.toml
        fi
        if [ -f "/etc/routedns/resolvers.toml" ]; then
                echo "# DIAB : INFO    : Found existing /etc/routedns/resolvers.toml - skipping blank creation"
                CreateRouteDNSResolvers=0
        else
                echo "# DIAB : INFO    : No existing /etc/routedns/resolvers.toml found - creating shell"
                CreateRouteDNSResolvers=1
                echo > /etc/routedns/resolvers.toml
        fi
        # Start building the config file...
        # Check if Logging has been requested
        if [ $DIAB_ENABLE_LOGGING ]; then
                if [ $DIAB_ENABLE_LOGGING -eq 1 ]; then
                        echo "# DIAB : INFO    : DIAB_ENABLE_LOGGING set. Enabling logging."
                        echo "-- Enabling Logging (set Logging=0 to disable)" >> /etc/dnsdist/dnsdist.conf
                        echo "Logging=1" >> /etc/dnsdist/dnsdist.conf
                else
                        echo "# DIAB : INFO    : DIAB_ENABLE_LOGGING not set. Disabling logging."
                        echo "-- Disable Logging (set Logging=1 to enable)" >> /etc/dnsdist/dnsdist.conf
                        echo "Logging=0" >> /etc/dnsdist/dnsdist.conf
                fi
        fi
        cat << EOF >> /etc/dnsdist/dnsdist.conf
-- Create ACL to allow all access (assuming firewalls!)
addACL('0.0.0.0/0')
EOF
        if [ $IPV6 -eq 1 ]; then
                echo "addACL('::/0')" >> /etc/dnsdist/dnsdist.conf
        fi
        echo "--" >> /etc/dnsdist/dnsdist.conf
        # Check for/enable the webserver
        if [ $DIAB_ENABLE_WEBSERVER ]; then
                if [ $DIAB_ENABLE_WEBSERVER -eq 1 ]; then
                        # Check we have a password specified - generate one if not
                        if [ -f $DIAB_WEB_PASSWORD ]; then
                                export DIAB_WEB_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
                                echo "# DIAB : INFO    : DIAB_ENABLED_WEBSERVER is set, but DIAB_WEB_PASSWORD is not."
                                echo "# DIAB : INFO    : Generated DIAB_WEB_PASSWORD as $DIAB_WEB_PASSWORD"
                        fi
                        # Check ew have an APIKEY specified - generate one if not
                        if [ -f $DIAB_WEB_APIKEY ]; then
                                export DIAB_WEB_APIKEY=`echo $DIAB_WEB_PASSWORD | rev`
                                echo "# DIAB : INFO    : DIAB_ENABLED_WEBSERVER is set, but DIAB_WEB_APIKEY is not."
                                echo "# DIAB : INFO    : Generated DIAB_WEB_APIKEY as $DIAB_WEB_APIKEY"
                        fi
                        # Write webserver configuration
                        echo "webserver(\"0.0.0.0:8083\", \"$DIAB_WEB_PASSWORD\", \"$DIAB_WEB_APIKEY\", {}, \"$DIAB_TRUSTED_LANS\")" >> /etc/dnsdist/dnsdist.conf
                        echo "# DIAB : INFO    : Webserver will be accessible at http://$ContainerIP:8083"
                fi
        fi
        # Check for/enable base DNS...
        if [ $DIAB_ENABLE_DNS ]; then
                if [ $DIAB_ENABLE_DNS -eq 1 ]; then
                        echo "# DIAB : INFO    : DIAB_ENABLE_DNS is set.  Enabling basic DNS at $ContainerIP:53"
                        cat << EOF >> /etc/dnsdist/dnsdist.conf
-- add basic DNS
addLocal('0.0.0.0:53', { reusePort=true })
EOF
                        if [ $IPV6 -eq 1 ]; then
                                echo "addLocal('[::]:53'" >> /etc/dnsdist/dnsdist.conf
                        fi
                        echo "--" >> /etc/dnsdist/dnsdist.conf
                fi
        fi
        # Check for/enable DoT...
        if [ $DIAB_ENABLE_DOT ]; then
                if [ $DIAB_ENABLE_DOT -eq 1 ]; then
                        echo "# DIAB : INFO    : DIAB_ENABLE_DOT is set.  Attempting to enable DoT at $ContainerIP:853"
                        echo "                   Ensure your SSL certificates contain hostnames which match any provided for $ContainerIP"
                        # Check for SSL files
                        if [ -f /ssl/cert.pem ] && [ -f /ssl/key.pem ]; then
                                cat << EOF >> /etc/dnsdist/dnsdist.conf
-- DoT Configuration
-- Includes path for certs in /ssl and bind on all interfaces
-- By default listens on port 853.
addTLSLocal("0.0.0.0", "/ssl/cert.pem", "/ssl/key.pem", { doTCP=true, reusePort=true, tcpFastOpenSize=64 })
EOF
                                if [ $IPV6 -eq 1 ]; then
                                        echo "addTLSLocal(\"[::]\", \"/ssl/cert.pem\", \"/ssl/key.pem\", { doTCP=true, reusePort=true, tcpFastOpenSize=64 })" >> /etc/dnsdist/dnsdist.conf
                                fi
                                echo "--" >> /etc/dnsdist/dnsdist.conf
                        else
                                echo "# DIAB : WARNING : DIAB_ENABLE_DOT is set but /ssl files are missing. Cannot start DoT".
                        fi
                fi
        fi
        # Check for/enable DOH...
        if [ $DIAB_ENABLE_DOH ]; then
                echo "# DIAB : INFO    : DIAB_ENABLE_DOH is set.  Attempting to enable DoH (secure on TCP 443 + insecure on TCP 8053)"
                if [ $DIAB_ENABLE_DOH -eq 1 ]; then
                        # Check for SSL files
                        if [ -f /ssl/cert.pem ] && [ -f /ssl/key.pem ]; then
                                echo "# DIAB : INFO    : SSL files found - enabling DoH secure server at https://$ContainerIP:443/dns-query"
                                echo "                   Ensure your SSL certificates contain hostnames which match any provided for $ContainerIP"
                                cat << EOF >> /etc/dnsdist/dnsdist.conf
-- DoH Configuration
-- Includes path for certs in /ssl and bind on all interfces
-- By default listens on port 443
addDOHLocal("0.0.0.0", "/ssl/cert.pem", "/ssl/key.pem", "/dns-query", { doTCP=true, reusePort=true, tcpFastOpenSize=64, trustForwardedForHeader=true })
EOF
                                if [ $IPV6 -eq 1 ]; then
                                        echo "addDOHLocal(\"[::]\", \"/ssl/cert.pem\", \"/ssl/key.pem\", \"/dns-query\", { doTCP=true, reusePort=true, tcpFastOpenSize=64, trustForwardedForHeader=true })" >> /etc/dnsdist/dnsdist.conf
                                fi
                                echo "--" >> /etc/dnsdist/dnsdist.conf
                        else
                                echo "# DIAB : WARNING : SSL files NOT found - only able to enable DoH insecure server"
                        fi
                        echo "# DIAB : INFO    : Enabling DoH insecure server at http://$ContainerIP:8053/dns-query"
                        cat << EOF >> /etc/dnsdist/dnsdist.conf
-- DoH **INSECURE** configuration.
-- No /ssl/cert.pem and/or /ssl/key.pem found - can only run insecurely - bind on all interfaces
-- Listening on port 8053
-- NB : Since the DoH queries are simple HTTPS requests, the server can be hidden behind Nginx or HAproxy
addDOHLocal("0.0.0.0:8053", nil, nil, "/dns-query", { reusePort=true, trustForwardedForHeader=true })
EOF
                        if [ $IPV6 -eq 1 ]; then
                                echo "addDOHLocal("[::]:8053", nil, nil, "/dns-query", { reusePort=true, trustForwardedForHeader=true })" >> /etc/dnsdist/dnsdist.conf
                        fi
                        echo "--" >> /etc/dnsdist/dnsdist.conf
                fi
        fi
        # Add general configuration
        cat << EOF >> /etc/dnsdist/dnsdist.conf
-- set X(int) number of queries to be allowed per second from a IP
addAction(MaxQPSIPRule(50), DropAction())
--  drop ANY queries sent over udp
addAction(AndRule({QTypeRule(DNSQType.ANY), TCPRule(false)}), DropAction())
-- set X number of entries to be in dnsdist cache by default
-- memory will be preallocated based on the X number
pc = newPacketCache(10000, {maxTTL=86400})
getPool(""):setCache(pc)
-- server policy to choose the downstream servers for recursion
setServerPolicy(leastOutstanding)
-- define ECS
setECSOverride(true)
setECSSourcePrefixV4(32)
setECSSourcePrefixV6(128)
setMaxTCPConnectionsPerClient(1000)   -- set X(int) for number of tcp connections from a single client. Useful for rate limiting the concurrent connections.
setMaxTCPQueriesPerConnection(100)    -- set X(int) , similiar to addAction(MaxQPSIPRule(X), DropAction())
--
EOF
        # Check for dnsdist healthcheck override.  By default these are every second, which may pollute server logs
        # Setting higher will reduce messages but may slow down failover in some situations
        if [ $DIAB_CHECKINTERVAL ]; then
                # Provide the override
                IntervalInsertion=",checkInterval=$DIAB_CHECKINTERVAL"
        else
                # None found - leave default (1 second)
                IntervalInsertion=""
        fi
        # Check for inbound privacy
        if [ $DIAB_ENABLE_INBOUND_PRIVACY ]; then
                if [ $DIAB_ENABLE_INBOUND_PRIVACY -eq 1 ]; then
                        UCSInsertion="useClientSubnet=false"
                else
                        UCSInsertion="useClientSubnet=true"
                fi
        fi
        # Process and add specified DIAB_UPSTREAM_IP_AND_PORT values
        echo "-- Backend DNS servers" >> /etc/dnsdist/dnsdist.conf
        Working=`echo $DIAB_UPSTREAM_IP_AND_PORT | sed "s/ //g"`
        Working=`echo $Working | sed "s/\r//g;"`
        WorkingCount=0
        for i in $(echo $Working | sed "s/,/ /g"); do
                TempCount=`expr $WorkingCount + 1`
                echo "# DIAB : INFO    : Processing upstream '$i' (Order=$TempCount)"
                # Grab identifiers...
                WorkingPrefix=`echo $i | cut -c1-5`
                WorkingSuffixa=${i: -3}
                WorkingSuffixb=${i: -2}
                Identified=0
                IFS=',' read -ra UpstreamName <<< "$DIAB_UPSTREAM_NAME"
                USN=${UpstreamName[$WorkingCount]}
                #echo "Working Prefix : $WorkingPrefix"
                #echo "Working SuffixA : $WorkingSuffixa"
                #echo "Working SuffixB : $WorkingSuffixb"
                #echo "USN = ${UpstreamName[$WorkingCount]}"
                if [ $WorkingPrefix == "https" ]; then
                        echo "# DIAB : INFO    : $i appears to be a DoH server"
                        if [ $Identified -eq 0 ]; then
                                if [ $CreateRouteDNSListeners -eq 1 ]; then
                                        echo "# DIAB : INFO    : Building routedns listener config for $i (DoH)"
                                        cat << EOF >> /etc/routedns/resolvers.toml
[resolvers.routedns$WorkingCount]
address = "$i{?dns}"
protocol = "doh"
EOF
                                fi
                                if [ $DIAB_ENABLE_OUTBOUND_PRIVACY ]; then
                                        if [ $DIAB_ENABLE_OUTBOUND_PRIVACY -eq 1 ]; then
                                                cat << EOF >> /etc/routedns/resolvers.toml
ecs-op = "privacy"
ecs-prefix4 = 16
ecs-prefix6 = 64
EOF
                                        fi
                                fi
                                if [ $CreateRouteDNSResolvers -eq 1 ]; then
                                        echo "# DIAB : INFO    : Building routedns resolver config for $i (DoH)"
                                        cat << EOF >> /etc/routedns/listeners.toml
[listeners.routedns$WorkingCount-udp]
address = ":900$WorkingCount"
protocol = "udp"
resolver = "routedns$WorkingCount"

[listeners.routedns$WorkingCount-tcp]
address = ":900$WorkingCount"
protocol = "tcp"
resolver = "routedns$WorkingCount"
EOF
                                        cat << EOF >> /etc/dnsdist/dnsdist.conf
newServer({address="0.0.0.0:900$WorkingCount",name="$USN",$UCSInsertion$IntervalInsertion,order=$TempCount})
EOF
                                        if [ $IPV6 -eq 1 ]; then
                                                echo "newServer({address=\"0.0.0.0:900$WorkingCount\",name=\"$USN\",UCSInsertion$IntervalInsertion,order=$TempCount})" >> /etc/dnsdist/dnsdist.conf
                                        fi
                                fi
                                Identified=1
                        fi
                fi
                if [ $WorkingSuffixa == "853" ]; then
                        echo "# DIAB : INFO    : $i appears to be a DoT server"
                        if [ $Identified -eq 0 ]; then
                                if [ $CreateRouteDNSListeners -eq 1 ]; then
                                        echo "# DIAB : INFO    : Building routedns listener config for $i (DoT)"
                                        cat << EOF >> /etc/routedns/resolvers.toml
[resolvers.routedns$WorkingCount]
address = "$i"
protocol = "dot"
EOF
                                fi
                                if [ $DIAB_ENABLE_OUTBOUND_PRIVACY ]; then
                                        if [ $DIAB_ENABLE_OUTBOUND_PRIVACY -eq 1 ]; then
                                                cat << EOF >> /etc/routedns/resolvers.toml
ecs-op = "privacy"
ecs-prefix4 = 16
ecs-prefix6 = 64
EOF
                                        fi
                                fi
                                if [ $CreateRouteDNSResolvers -eq 1 ]; then
                                        echo "# DIAB : INFO    : Building routedns resolver config for $i (DoT)"
                                        cat << EOF >> /etc/routedns/listeners.toml
[listeners.routedns$WorkingCount-udp]
address = ":900$WorkingCount"
protocol = "udp"
resolver = "routedns$WorkingCount"

[listeners.routedns$WorkingCount-tcp]
address = ":900$WorkingCount"
protocol = "tcp"
resolver = "routedns$WorkingCount"
EOF
                                        cat << EOF >> /etc/dnsdist/dnsdist.conf
newServer({address="0.0.0.0:900$WorkingCount",name="$USN",$UCSInsertion$IntervalInsertion,order=$TempCount})
EOF
                                        if [ $IPV6 -eq 1 ]; then
                                                echo "newServer({address=\"0.0.0.0:900$WorkingCount\",name=\"$USN\",$UCSInsertion$IntervalInsertion,order=$TempCount})" >> /etc/dnsdist/dnsdist.conf
                                        fi
                                fi
                                Identified=1
                        fi
                fi
                if [ $WorkingSuffixb == "53" ]; then
                        echo "# DIAB : INFO    : $i appears to be a plain old DNS server"
                        if [ $Identified -eq 0 ]; then
                                cat << EOF >> /etc/dnsdist/dnsdist.conf
newServer({address="$i",name="$USN",$UCSInsertion$IntervalInsertion,order=$TempCount})
EOF
                                Identified=1
                        fi
                fi
                echo "# DIAB : INFO    : Added $i as $USN"
                WorkingCount=`expr $WorkingCount + 1`
                Identified=0
        done
        # Declare "connectivitycheck" servers
        cat << EOF >> /etc/dnsdist/dnsdist.conf
--
-- Declare Google Connectivity Check servers...
AllowedGoogle=newSuffixMatchNode()
AllowedGoogle:add("metric.gstatic.com")
AllowedGoogle:add("client1.google.com")
AllowedGoogle:add("client2.google.com")
AllowedGoogle:add("client3.google.com")
AllowedGoogle:add("client4.google.com")
AllowedGoogle:add("client5.google.com")
AllowedGoogle:add("connectivitycheck.gstatic.com")
--
EOF
        # Check for allowed external hosts
        echo "AllowedDomains=newDNSNameSet()" >> /etc/dnsdist/dnsdist.conf
        if [ $DIAB_ALLOWED_EXTERNALLY ]; then
                echo "# DIAB : INFO    : DIAB_ALLOWED_EXTERNALLY is set"
                Working=`echo $DIAB_ALLOWED_EXTERNALLY | sed "s/ //g"`
                for i in $(echo $Working | sed "s/,/ /g"); do
                        echo "# DIAB : INFO    : Adding $i to hostnames allowed for external hosts"
                        echo "AllowedDomains:add(newDNSName(\"$i\"))" >> /etc/dnsdist/dnsdist.conf
                done
                echo "--" >> /etc/dnsdist/dnsdist.conf
        fi
        # Check for trusted LANs
        echo "-- Define Trusted LANs" >> /etc/dnsdist/dnsdist.conf
        echo "TrustedLAN=newNMG()" >> /etc/dnsdist/dnsdist.conf
        if [ $DIAB_TRUSTED_LANS ]; then
                echo "# DIAB : INFO    : DIAB_TRUSTED_LANS is set"
                Working=`echo $DIAB_TRUSTED_LANS | sed "s/ //g"`
                for i in $(echo $Working | sed "s/,/ /g"); do
                        echo "# DIAB : INFO    : Adding $i to trusted LANs"
                        echo "TrustedLAN:addMask(\"$i\")" >> /etc/dnsdist/dnsdist.conf
                done
                echo "--" >> /etc/dnsdist/dnsdist.conf
        fi
        # Add the logging, checkInternal and orderedLeastOutstanding functions to dnsdist.conf
        cat << EOF >> /etc/dnsdist/dnsdist.conf
-- Simple logging function
function Log(msg)
   if (Logging==1) then
        print("# DIAB : LOG     : "..msg)
   end
end
-- Check query original and handle accordingly...
function checkInternal(dq)
        -- Record the requested DNS name
        workingQuery = newDNSName(dq.qname:toString())
        workingQueryTxt = dq.qname:toString()
        remoteHost=dq.remoteaddr:toString()
        -- If the requesting host is 'trusted'
        if(TrustedLAN:match(dq.remoteaddr))then
                Log("INTERNAL query from ("..remoteHost..") for ("..workingQueryTxt..") - Allowing.")
                return DNSAction.Allow
        else
                Log("EXTERNAL query from ("..remoteHost..") for ("..workingQueryTxt..") - Checking...")
                if(AllowedDomains:check(dq.qname))
                then
                        Log("\\\- EXTERNAL check - ("..workingQueryTxt..") is on the allowed list...Allowing.")
                        return DNSAction.Allow
                else
                        if (AllowedGoogle:check(workingQuery))
                        then
                                Log("\\\- EXTERNAL check - ("..workingQueryTxt..") is part of Google Connectivity. Allowing.")
                                return DNSAction.Allow
                        else
                                Log("\\\- EXTERNAL check - ("..workingQueryTxt..") not on allowed list...Refusing.")
                                return DNSAction.Refused
                        end
                end
        end
end
addAction(AllRule(), LuaAction(checkInternal))
-- Updated orderedLeastOutstanding function from https://github.com/sysadminblog/dnsdist-configs/blob/master/orderedLeastOutstanding.lua
-- Modified by the diab project
function orderedLeastOutstanding(servers, dq)
        -- If there is only one or 0 servers in the table, return it to stop further processing
        if (#servers == 0 or #servers == 1) then
                return servers
        end
        -- Create server list table
        serverlist = {}
        -- Loop over each server for the pool
        i = 1
        while servers[i] do
                workingname = servers[i].name
                -- We only care if the server is currently up
                if (servers[i].upStatus == true) then
                        -- server shows up (via healthcheck) but may not have been marked down...
                        -- test for drop flags and reset if required
                        if (servers[i]:isUp() == true) then
                                -- server has NOT been marked down....
                                --
                                -- test for DROP COUNT here when ready...
                                -- set drop flags once ready
                                --
                                -- Retrieve the order for the server
                                order = servers[i].order
                                -- Create table for this order if not existing
                                if type(serverlist[order]) ~= "table" then
                                        serverlist[order] = {}
                                end
                                -- Insert this server to the ordered table
                                table.insert(serverlist[order], servers[i])
                        else
                                Log("DNS server "..workingname.." isUp is FALSE (marked DOWN).")
                        end
                else
                        Log("DNS server "..workingname.." upStatus is FALSE (healthcheck failed).")
                end
                -- Increment counter for next loop
                i=i+1
        end
        -- Get the lowest key in the table so that we use the lowest ordered server(s)
        for k,v in pairs (serverlist) do
                if lowest == nil then
                        lowest = k
                else
                        if k < lowest then
                                lowest = k
                        end
                end
        end
        -- Double check the server list has a value/is defined. I don't think this should
        -- ever happen, but you can't be too safe. If it has no value, then return the server
        -- list.
        if serverlist[lowest] == nil then
                return leastOutstanding.policy(servers, dq)
        end
        -- Return the lowest ordered server list to the leastOutstanding function
        return leastOutstanding.policy(serverlist[lowest], dq)
end
setServerPolicyLua("orderedLeastOutstanding", orderedLeastOutstanding)
EOF
        if [ $DIAB_ENABLE_CLI ]; then
                if [ $DIAB_ENABLE_CLI -eq 1 ]; then
                        echo "# DIAB : INFO    : Enabling CLI access on port 5199..."
                        echo "# DIAB : INFO    : CLI is accessible from within the container by running:"
                        echo "                   dnsdist -c -C /etc/dnsdist/dnsdist.conf"
                        secureKey=`echo "makeKey()" | dnsdist -l 127.0.0.1:999 | tail -1`
                        echo "-- Enable CLI access" >> /etc/dnsdist/dnsdist.conf
                        echo "controlSocket('127.0.0.1:5199')" >> /etc/dnsdist/dnsdist.conf
                        if [ $IPV6 -eq 1 ]; then
                                echo "controlSocket('[::1]:5199')" >> /etc/dnsdist/dnsdist.conf
                        fi
                        echo $secureKey >> /etc/dnsdist/dnsdist.conf
                fi
        fi
        echo "# DIAB : INFO    : diab V$DV configurator finished!"
        echo "#"
fi
