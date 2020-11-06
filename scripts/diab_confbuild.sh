#!/bin/bash

# Check for existing config file...
if [ -f "/etc/dnsdist/dnsdist.conf" ]; then
        # Config present - do nothing
        echo Found existing /etc/dnsdist/dnsdist.conf - skipping config build

else
        mkdir -p /etc/dnsdist
        # Start building the config file...
        if [ $DIAB_ENABLE_LOGGING -eq 1 ]; then
                echo "-- Enabling Logging" >> /etc/dnsdist/dnsdist.conf
                echo "Logging=1" >> /etc/dnsdist/dnsdist.conf
        fi
        cat << EOF >> /etc/dnsdist/dnsdist.conf

-- Create ACL to allow all access (assuming firewalls!)
addACL('0.0.0.0/0')
EOF
        # Check for/enable the webserver
        if [ $DIAB_ENABLE_WEBSERVER -eq 1 ]; then
                if [ $DIAB_WEB_APIKEY ]; then
                        WebAPIKey=$DIAB_WEB_APIKEY
                else
                        WebAPIKey=`echo $DIAB_WEB_PASSWORD | rev`
                fi

                echo "webserver(\"0.0.0.0:8083\", \"$DIAB_WEB_PASSWORD\", \"$WebAPIKey\", {}, \"$DIAB_TRUSTED_LANS\")" >> /etc/dnsdist/dnsdist.conf
        fi

        # Check for/enable base DNS...
        if [ $DIAB_ENABLE_DNS -eq 1 ]; then
        cat << EOF >> /etc/dnsdist/dnsdist.conf

-- add normal DNS
addLocal('0.0.0.0:53', { reusePort=true })

EOF
        fi

        # Check for/enable DoT...
        if [ $DIAB_ENABLE_DOT -eq 1 ]; then
cat << EOF >> /etc/dnsdist/dnsdist.conf
-- path for certs and listen address for DoT ipv4,
-- by default listens on port 853.
-- Set X(int) for tcp fast open queue size.
addTLSLocal("0.0.0.0", "/ssl/cert.pem", "/ssl/key.pem", { doTCP=true, reusePort=true, tcpFastOpenSize=64 })

EOF
        fi

        # Check for/enable DOH...
        if [ $DIAB_ENABLE_DOH -eq 1 ]; then
cat << EOF >> /etc/dnsdist/dnsdist.conf
-- path for certs and listen address for DoH ipv4,
-- by default listens on port 443.
-- Set X(int) for tcp fast open queue size.
--
-- In this example we listen directly on port 443. However, since the DoH queries are simple HTTPS requests, the server can be hidden behind Nginx or Haproxy.
addDOHLocal("0.0.0.0", "/ssl/cert.pem", "/ssl/key.pem", "/dns-query", { doTCP=true, reusePort=true, tcpFastOpenSize=64, trustForwardedForHeader=true })
addDOHLocal("0.0.0.0:8053", nil, nil, "/dns-query", { reusePort=true, trustForwardedForHeader=true })
EOF
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

setMaxTCPConnectionsPerClient(1000)    -- set X(int) for number of tcp connections from a single client. Useful for rate limiting the concurrent connections.
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
                Working=`echo $DIAB_ALLOWED_EXTERNALLY | sed "s/ //g"`
                for i in $(echo $Working | sed "s/,/ /g"); do
                        echo "AllowedDomains:add(newDNSName(\"$i\"))" >> /etc/dnsdist/dnsdist.conf
                done
                echo >> ./config.conf
        fi

        # Check for trusted LANs
        echo "TrustedLAN=newNMG()" >> /etc/dnsdist/dnsdist.conf
        if [ $DIAB_TRUSTED_LANS ]; then
                Working=`echo $DIAB_TRUSTED_LANS | sed "s/ //g"`
                for i in $(echo $Working | sed "s/,/ /g"); do
                        echo "TrustedLAN:addMask(\"$i\")" >> /etc/dnsdist/dnsdist.conf
                done
                echo >> /etc/dnsdist/dnsdist.conf
        fi

        cat << EOF >> /etc/dnsdist/dnsdist.conf

-- Simple logging function
function Log(msg)
   if (Logging==1) then
        print(msg)
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

fi
