#!/bin/bash
echo "#"
echo "# DIAB : INFO    : Starting diab V1.2"
# Check for existing config file...
if [ -f "/etc/dnsdist/dnsdist.conf" ]; then
        # Config present - do nothing
        echo "# DIAB : INFO    : Found existing /etc/dnsdist/dnsdist.conf - skipping config build"
        echo "# DIAB : WARNING : If you have changed Docker environment variables, they will not take effect as the existing file wlil be used."
else
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
        echo "# DIAB : INFO    : Next DNS hop configured as $DIAB_UPSTREAM_NAME ($DIAB_UPSTREAM_IP_AND_PORT)"
        # Start building the config file...
        mkdir -p /etc/dnsdist
        if [ $DIAB_ENABLE_LOGGING ]; then
                if [ $DIAB_ENABLE_LOGGING -eq 1 ]; then
                        echo "# DIAB : INFO    : DIAB_ENABLE_LOGGING set. Enabling logging."
                        echo "-- Enabling Logging" >> /etc/dnsdist/dnsdist.conf
                        echo "Logging=1" >> /etc/dnsdist/dnsdist.conf
                fi
        fi
        cat << EOF >> /etc/dnsdist/dnsdist.conf
-- Create ACL to allow all access (assuming firewalls!)
addACL('0.0.0.0/0')
EOF
        # Check for/enable the webserver
        if [ $DIAB_ENABLE_WEBSERVER ]; then
                if [ $DIAB_ENABLE_WEBSERVER -eq 1 ]; then
                        # Check we have a password specified - generate one if not
                        if [ -f $DIAB_WEB_PASSWORD ]; then
                                export DIAB_WEB_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
                                echo "# DIAB : INFO    : DIAB_ENABLED_WEBSERVER is set, but DIAB_WEB_PASSWORD is not."
                                echo "# DIAB : INFO    : Generated DIAB_WEB_PASSWORD as $DIAB_WEB_PASSWORD"
                        fi
                        if [ -f $DIAB_WEB_APIKEY ]; then
                                export DIAB_WEB_APIKEY=`echo $DIAB_WEB_PASSWORD | rev`
                                echo "# DIAB : INFO    : DIAB_ENABLED_WEBSERVER is set, but DIAB_WEB_APIKEY is not."
                                echo "# DIAB : INFO    : Generated DIAB_WEB_APIKEY as $DIAB_WEB_APIKEY"
                        fi
                        echo "webserver(\"0.0.0.0:8083\", \"$DIAB_WEB_PASSWORD\", \"$DIAB_WEB_APIKEY\", {}, \"$DIAB_TRUSTED_LANS\")" >> /etc/dnsdist/dnsdist.conf
                fi
        fi
        # Check for/enable base DNS...
        if [ $DIAB_ENABLE_DNS ]; then
                if [ $DIAB_ENABLE_DNS -eq 1 ]; then
                echo "# DIAB : INFO    : DIAB_ENABLE_DNS is set.  Enabling basic DNS on port 53"
                cat << EOF >> /etc/dnsdist/dnsdist.conf
-- add basic DNS
addLocal('0.0.0.0:53', { reusePort=true })
EOF
                fi
        fi
        # Check for/enable DoT...
        if [ $DIAB_ENABLE_DOT ]; then
                if [ $DIAB_ENABLE_DOT -eq 1 ]; then
                        echo "# DIAB : INFO    : DIAB_ENABLE_DOT is set.  Attempting to enable DoT on TCP 853"
                        # Check for SSL files
                        if [ -f /ssl/cert.pem ] && [ -f /ssl/key.pem ]; then
                                cat << EOF >> /etc/dnsdist/dnsdist.conf
-- path for certs and listen address for DoT ipv4,
-- by default listens on port 853.
-- Set X(int) for tcp fast open queue size.
addTLSLocal("0.0.0.0", "/ssl/cert.pem", "/ssl/key.pem", { doTCP=true, reusePort=true, tcpFastOpenSize=64 })
EOF
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
                                echo "# DIAB : INFO    : SSL files found - enabling DoH secure server on TCP port 443"
                                cat << EOF >> /etc/dnsdist/dnsdist.conf
-- DoH configuration with path for certs in /ssl, listening on TCP port 443.
-- Set X(int) for tcp fast open queue size.
--
addDOHLocal("0.0.0.0", "/ssl/cert.pem", "/ssl/key.pem", "/dns-query", { doTCP=true, reusePort=true, tcpFastOpenSize=64, trustForwardedForHeader=true })
EOF
                        else
                                echo "# DIAB : WARNING : SSL files NOT found - only able to enable DoH insecure server"
                        fi
                        echo "# DIAB : INFO    : Enabling DoH insecure server on TCP port 8053"
                        cat << EOF >> /etc/dnsdist/dnsdist.conf
-- Since the DoH queries are simple HTTPS requests, the server can be hidden behind Nginx or Haproxy.
-- To allow an HTTPS front end to proxy, we will also listen on port 8053 (insecure)
addDOHLocal("0.0.0.0:8053", nil, nil, "/dns-query", { reusePort=true, trustForwardedForHeader=true })
EOF
                fi
        fi
        # Add general config and define back end DNS server...
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
-- Here we define our backend, the pihole dns server
newServer({address="$DIAB_UPSTREAM_IP_AND_PORT", name="$DIAB_UPSTREAM_NAME", useClientSubnet=true})
EOF

        # Declare "connectivitycheck" servers
        cat << EOF >> /etc/dnsdist/dnsdist.conf
-- Declare Google Connectivity Check servers...
AllowedGoogle=newSuffixMatchNode()
AllowedGoogle:add("metric.gstatic.com")
AllowedGoogle:add("client1.google.com")
AllowedGoogle:add("client2.google.com")
AllowedGoogle:add("client3.google.com")
AllowedGoogle:add("client4.google.com")
AllowedGoogle:add("client5.google.com")
EOF

        # Check for allowed external hosts
        echo "AllowedDomains=newDNSNameSet()" >> /etc/dnsdist/dnsdist.conf
        if [ $DIAB_ALLOWED_EXTERNALLY ]; then
                echo "# DIAB : INFO    : DIAB_ALLOWED_EXTERNALLY is set"
                Working=`echo $DIAB_ALLOWED_EXTERNALLY | sed "s/ //g"`
                for i in $(echo $Working | sed "s/,/ /g"); do
                        echo "# DIAB : INFO    : Adding $i to hostnames allowed by external hosts"
                        echo "AllowedDomains:add(newDNSName(\"$i\"))" >> /etc/dnsdist/dnsdist.conf
                done
                echo >> ./config.conf
        fi
        # Check for trusted LANs
        echo >> /etc/dnsdist.conf
        echo "TrustedLAN=newNMG()" >> /etc/dnsdist/dnsdist.conf
        if [ $DIAB_TRUSTED_LANS ]; then
                echo "# DIAB : INFO    : DIAB_TRUSTED_LANS is set"
                Working=`echo $DIAB_TRUSTED_LANS | sed "s/ //g"`
                for i in $(echo $Working | sed "s/,/ /g"); do
                        echo "# DIAB : INFO    : Adding $i to trusted LANs"
                        echo "TrustedLAN:addMask(\"$i\")" >> /etc/dnsdist/dnsdist.conf
                done
                echo >> /etc/dnsdist/dnsdist.conf
        fi
        # Add the logging and checkInternal functions to dnsdist.conf
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
EOF
        echo "# DIAB : INFO    : Startup script complete"
        echo "#"
fi
