# diab

Private "**D**NS **I**n **A** **B**ox" - is a lightweight (ish) container designed for to provide secure, roaming DNS for use with piHole and Traefik.

The use-case is quite specific, but may be surprisingly useful for many.  Read on.

## Why encrypt DNS?
Normal DNS queries are sent "plaintext" - meaning anyone or anything (person or code) with access to your traffic can see which sites your devices are requesting.  This could happen between your device and your DNS server, or your DNS server and your ISP's server.  Whilst a DNS request may not indicate a subsequent connection to a returned address, it's a fairly good bet that a request would probably be followed up by a connection to that address.

DNS-over-HTTPS (DoH) and DNS-over-TLS (DoT) and DNSCrypt have been created to allow encryption of DNS queries so that requests can be encrypted - so only your device(s) and your DNS server of choice know what you requested, until an actual connection is initiated. Traffic inspection can still show IP addresses, although with the declining IPv4 address space and prevalance of virtual hosting, IP addresses are not a guarantee of which sites may be connected to - but SNI can still reveal which site was requested.

DNS encryption combined with ESNI makes things a bit better, and *diab* is here to assist with the former....

## The use case

As mentioned, this is quite specific - but is designed to keep as much of 'your' device traffic as secure as can be.

The assumption is that you already (or want to):
- Run your own Linux server at home
- Run Docker on said server
- Have an internet connection with a unique (static or dynamic) external IP address
- Have a home router with port forwarding capabilities
- Run your own local DNS filtering (i.e. piHole)
-- You don't want devices/browsers going to "other" DNS providers
-- You may already have piHole (or other DNS tool) configured to securely talk to another DNS service, i.e. OpenDNS via DNSCrypt
- Run your own VPN (i.e. WireGuard) to secure your mobile device traffic - and get piHole cover when roaming
-- You want to use the "Always-On" and "Block connections without VPN" options on your mobile
- *Don't* want to operate a "public" facing DNS service, that you need to connect to your VPN....
- *Don't* want a mobile device to report "No internet connection" when using restricted DNS

### The browser and/or device dilemma

Firefox supports DoH, and (unless you switch it off) might start using it with DNS servers you can't control (i.e. bypassing piHole).  You can't block port 443 outbound, as you'd block all secure web traffic...

Chrome (and Android) support DoT (which uses TCP port 853, thus *can* be blocked) - but *only* if the specified DNS host offers it as well as plaintext - and piHole doesn't provide DoT...

### Make sense?

As an example, the author runs a Linux box running OpenMediaVault, running Docker.  Docker is hosting:
 - a piHole container to provide DNS (with adblocking) to the LAN
 - a WireGuard container to provide a VPN "back to the LAN" when roaming away from home WiFi (also enabling piHole adblock coverage when roaming)
 -- piHole is configured to use a DNSCrypt (with DNSSEC) connection to an external filter (OpenDNS).  
 - a Traefik container for a variety of things, but it handles dynamic SSL certificate provision

However, the author's ideal is to ensure Android's new "Always-On" and "Block connections without VPN" settings are "on" - and that "Private DNS" is always set to a trusted host (i.e. the author's own).

You might at this point think "*Hang on, won't WireGuard be encrypting the DNS traffic to piHole, and DNScrypt encrypting all the outgoing queries?*" - and you'd partially be right...*however*:

1) WireGuard needs a hostname or IP to connect to.  The author's IP is dynamic - so Dynamic DNS is in use to update a known hostname for WireGuard to connect to
2) WireGuard needs access to DNS to lookup the hostname, which it *must* do before it can connect.
3) The only way to set DNS in Android is either)
-- in WiFi settings ('standard' DNS only, i.e. *not* encrypted) or
-- use Private DNS
4) "Private DNS" on Android has 3 options - "Off", "Automatic" or a user provided hostname can be forced
-- If "Off" is set, plaintext DNS will be used
-- If "Automatic" is used, Android  will connect to a user provided hostname (if provided) or any it can 'find' (which may not be yours, i.e. Google or QuadDNS) - even if WireGuard later overrides it
-- If you force a user provided hostname, Android will ONLY use secure DNS to lookup WireGuard
7) Thus you need to provide a secure DNS server for your initial connection. You *could* use an external service, but skips piHole etc...and...
8) You probably don't want any secure DNS server you provide to be publically available but....
9) Your roaming (cellular) IP will change frequently - so you can't firewall it to check clients before WireGuard has connected
10) Even once WireGuard connects, "Private DNS" will still be used - so it needs to be resolvable/accessible internally *and* externally
11) piHole doesn't offer DoT, so you can't just point at a piHole IP...

## The solution

*diab*.

diab exists to **securely** front **all** your internal *and* external DNS needs - in conjunction with piHole and Traefik.

Running as a Docker container on a macvlan interface (i.e. with it's own LAN IP) it will provide:

1) Standard (plaintext) DNS - *internally only* - forwarded to a DNS service of your choice
2) DoH - internally *and* externally - forwarded to a DNS service of your choice
3) DoT - internally *and* externally - forwarded to a DNS service of your choice

The assumption here is that the "DNS service of your choice" is already configured (i.e. piHole, or another DoT/DoH/DNSCrypt proxy to an external DNS). diab will just continue plugging into that - so all you need to do is change your DNS IP/host to the new diab IP.

Whilst diab will be externally available (via DoT and/or DoH) - it will only respond to queries it is allowed to.  As a "base set" it will allow Android mobile devices to resolve client1-5.google.com and connectivitycheck.gstatic.com - preventing a device from displaying "offline" alerts.

Over and above that, you can allow certain addresses on your domain to respond - i.e. Wireguard.

# Configuration

## Volumes

* `/your/ssl/folder:/ssl:ro` (needed for DoH and/or DoT - **must** contain *cert.pem* and *key.pem*)
* `/your/dnsdist/config/folder:/etc/dnsdist` (optional)
* `/etc/localtime:/etc/localtime:ro` (optional *but* ensures correct timestamps)
* `/etc/timezone:/etc/timezone:ro` (optional *but* ensures correct timestamps)

## Environment

* DIAB_ENABLE_DNS - Set this to 1 to enable "normal" DNS.  It will run on 0.0.0.0:53
* DIAB_ENABLE_DOT - Set this to 1 to enable DoT. It will run on 0.0.0.0:853 - and requires /ssl/cert.pem and /ssl/key.pem to be available via a bind mount volume.
* DIAB_ENABLE_DOH - Set this to 1 to enable DoT. It will run on 0.0.0.0:443 - and requires /ssl/cert.pem and /ssl/key.pem to be available via a bind mount volume.
** It will also enable an "insecure" DOH server on 0.0.0.0:8053 - which you can use with Traefik (see below)
* DIAB_ALLOWED_EXTERNALLY - Set this to a comma separated list of hostnames you want to resolve.  One should be your WireGuard hostname
* DIAB_ENABLE_LOGGING - Set this to 1 to enable textual messages in the Docker logs/stdout
* DIAB_ENABLE_ADVANCED_LOGGING - Set this to 1 to enable verbose messaging from dnsdist itself
* DIAB_ENABLE_WEBSERVER - Set to 1 to enable the dnsdist webserver.  It will run on 0.0.0.0:8053
* DIAB_TRUSTED_LANS - Set this to a comma separated list of netmasks you wish to allow, (i.e. 192.168.1.0/24,172.17.0.0/16)
* DIAB_UPSTREAM_IP_AND_PORT - Set this to the IP and port of your chosen DNS server (i.e. *1.2.3.4:53*)
* DIAB_UPSTREAM_NAME - Set this to a friendly name for your chosen DNS server (i.e. *piHole*) - it will show in the web interface and logs
* DIAB_WEB_PASSWORD - Set to whatever you want your webserver password to be.  The username can be anything.

## Network

Run the container either on a macvlan interface with it's own IP *or* in host mode.
If you choose to run in bridge mode, you will need to handle all port forwarding yourself, and DoT/DoH may fail, and is not supported.

## DNS Records

### External

You should create a CNAME record (i.e. *dns.yoursubdomain.yourdomain.com* and point it to either
- the dynamic DNS hostname you use to point to your dynamic host IP
- the static IP of your host, if you are lucky enough to have a static IP

### Internal

Setup a local DNS entry which matches the external *hostname* but point it to the macvlan LAN IP address of the container

## DoT (Port Forward)

On your router, forward all TCP 853 traffic to the macvlan LAN IP address of the container

## DoH (Port Forward)

### Without Traefik (assumes you have no other HTTPS/port 443 services)

On your router, forward all TCP 853 traffic to the macvlan LAN IP address of the container

### With Traefik

On your router, forward all TCP 443 traffic to the macvlan LAN IP address of your Traefik container

### Traefik Configuration (Container Labels)

* traefik.enable=true
* traefik.http.routers.doh.entryPoints=websecure (or whatever your https entrypoint is called)
* traefik.http.routers.doh.middlewares=doh@file
* traefik.http.routers.doh.rule=HostHeader(\`dns.yoursubdomain.yourdomain.com\`)
* traefik.http.routers.doh.service=doh
* traefik.http.routers.doh.tls=true
* traefik.http.routers.doh.tls.certresolver=your_traefik_cert_provider
* traefik.http.routers.doh.tls.domains[0].sans=*.yoursubdomain.yourdomain.com
* traefik.http.services.doh.loadbalancer.server.port=8053
* traefik.http.middlewares.mw_doh.headers.hostsProxyHeaders=X-Forwarded-For

### Traefik Configuration (Static Config)

To ensure diab sees the correct external IP of a client, you may need to update your Traefik https/websecure entrypoint to allow the use of host header.  Assuming your Traefik configuration is in TOML and your entrypoint is called *websecure* you should update it to look like the following:

`[entryPoints.websecure]`<br/>
`  address = ":443"`<br/>
`  [entryPoints.websecure.forwardedHeaders]`<br/>
`    insecure=true`<br/>
    
You will then need to restart Traefik, via `docker restart traefik`
dnsdist is already configured to handle X-Forwarded-For headers, but it will only function if the above is enabled in Traefik.

# Usage

## Docker Image/Container operation

If you have not used dnsdist before, it is advisable you set your required environment variables, ensure /ssl can be mounted to the container and start it.
Once configured and started, diab will check for the existence of /etc/dnsdist/dnsdist.conf
If the file does **not** exist, it will be created, but only within the running container.
If the file **does** exist (i.e. from a bind mounted volume, or a restarted container) it will be used.  

The only environment variable that operates outside of the configuration is *DIAB_ENABLE_ADVANCED_LOGGING*.  If you have a bind mounted volume containing dnsdist.conf and wish to change config, you will have to edit that file and restart the container, or remove it and allow the container to build one itself.

If you are happy with your running configuration, you can copy any built configuration out of the container to a local folder thus:<br/>

`cd /your/desired/host/folder`<br/>
`docker cp containername:/etc/dnsdist/dnsdist.conf ./dnsdist.conf`

# Routing

If you follow the above setup, you should the the following:

## External client (Request for an ADDRESS from a client [NOT within] DIAB_TRUSTED_LANS)

Mobile Device -> DoT Query 853 -> Router -> Port Forward 853 -> diab DoT Secure 853 -> PROCESS<br/>
Mobile Device -> DoH Query 443 -> Router -> Port Forward 443-> Traefik -> diab DoT Insecure 8053 -> PROCESS<br/>
or<br/>
Mobile Device -> DoH Query 443 -> Router -> Port Forward 443 -> diab DoH 443 -> PROCESS<br/>

...where PROCESS = Allow or Reject<br/>
Any request for an ADDRESS **[NOT]** within DIAB_ALLOWED_EXTERNALLY will be rejected.<br/>

## Internal client (Request for an ADDRESS from a client [WITHIN] DIAB_TRUSTED_LANS)

Device -> DNS Query 53 -> diab DNS port 53 -> Allow<br/>
Device -> DoT Query 853 -> diab DoT port 853 -> Allow<br/>
Device -> DoH Query 443 -> diab DoT port 443 -> Allow<br/>

# Notes

* dnsdist does not (itself) communicate *with* DoH or DoT *servers* - so if you want a secure "end to end" stream, you will need to provide one - either via a separate DoT/DoH proxy.  Some router firmware (for example Tomato) allow capture and routing of DNS over DNSCrypt to a chosen external endpoint.
* You could configure dnsdist.conf to add another standard DNS server, on an/other port - which chains to an/other DoT or DoH service/container on your LAN, as necessary - i.e.<br/> DNS/DoT/DoH -> diab Front -> pihole -> diab Rear -> External





