# diab

Private "**D**NS **I**n **A** **B**ox" - is a lightweight (ish) container designed for to provide secure, roaming DNS for use with piHole and Traefik.

The use-case is quite specific, but may be surprisingly useful for many.  Read on.

This container makes use of:
 - the [bitnami/minideb](https://hub.docker.com/r/bitnami/minideb/) image
 - the totally wonderful [dnsdist](https://dnsdist.org) - which provides the DoH, DoT and DNS front end functionality
 - routedns (https://github.com/folbricht/routedns) for DoT and DoH backend support
 - a modified version of orderedLeastOutstanding (https://github.com/sysadminblog/dnsdist-configs/blob/master/orderedLeastOutstanding.lua)
 - Some of the authors own scripting ([bash](https://www.gnu.org/software/bash/) and [lua](http://www.lua.org/))
 
## Why encrypt DNS?
Normal DNS queries are sent "plaintext" - meaning anyone or anything (person or code) with access to your traffic can see which sites your devices are requesting.  This could happen between your device and your DNS server, or your DNS server and your ISP's server.  Whilst a DNS request may not indicate a subsequent connection to a returned address, it's a fairly good bet that a request would probably be followed up by a connection to that address.

DNS-over-HTTPS (DoH) and DNS-over-TLS (DoT) and DNSCrypt have been created to allow encryption of DNS queries so that requests can be encrypted - so only your device(s) and your DNS server of choice know what you requested, until an actual connection is initiated. Traffic inspection can still show IP addresses, although with the declining IPv4 address space and prevalance of virtual hosting, IP addresses are not a guarantee of which sites may be connected to - but SNI can still reveal which site was requested.

Additionally, EDNS can reveal the IP of an originating machine, even to intermediate DNS servers.

DNS encryption combined with ESNI makes things a bit better, and *diab* is here to assist with the rest....

## The use case

As mentioned, this is quite specific - but is designed to keep as much of 'your' device traffic as secure as can be.

The assumption is that you already (or want to):
- Run or host your own Linux server 
- Run Docker on said server
- Have an internet connection with a unique (static or dynamic) external IP address
- Have a router with port forwarding capabilities
- Run your own DNS service/filtering (i.e. piHole)
-- You don't want devices/browsers going to "other" DNS providers
-- You may already have piHole (or other DNS tool) configured to securely talk to another DNS service, i.e. OpenDNS via DNSCrypt
- Run your own VPN (i.e. WireGuard) to secure your mobile device traffic (which means access to your piHole server when roaming!)
-- You want to use the "Always-On" and "Block connections without VPN" options on your mobile
- *Don't* want to make your DNS/piHole "public" facing (anyone might find/use it!)
- Just make it all look seamless!

If you want to setup your own Linux, OMV, Docker, Traefik and piHole box - read our article [https://site.gothtech.co.uk/articles/omv-portainer-traefik-letsencrypt](here).

If you want to setup WireGuard for the above setup - read our article [https://site.gothtech.co.uk/articles/omv-portainer-traefik-letsencrypt/wireguard-traefik](here).

### The browser and/or device dilemma

Firefox supports DoH, and (unless you switch it off) might start using it with DNS servers you can't control (i.e. bypassing your DNS).  You can't block port 443 outbound, as you'd block all secure web traffic...it's a blessing *and* a curse.

Chrome (and Android) support DoT (which uses TCP port 853, thus *can* be blocked) - but *only* if the specified DNS host offers an unencrypted service also, which means most people wont get it locally on the same IP as their DNS server - and piHole doesn't provide DoT (yet)...

### Making sense?

As an example, the author runs a Linux box running OpenMediaVault, running Docker.  Docker is hosting:
- a piHole container to provide DNS (with adblocking) to the LAN
- a WireGuard container to provide a VPN "back to the LAN" when roaming away from home WiFi (also enabling piHole adblock coverage when roaming)
-- piHole is configured to use an upstream DNSCrypt (with DNSSEC) connection to an external filter (OpenDNS).  
- a Traefik container for a variety of things, but it handles dynamic SSL certificate provision

However, the author's ideal is to ensure Android's new "Always-On" and "Block connections without VPN" settings are "on" - and that "Private DNS" is always set to a trusted host (i.e. the author's own) *without* making that Private DNS service accessible to anyone else.

You might at this point think "*Hang on, won't WireGuard be encrypting the DNS traffic to piHole, and DNScrypt encrypting all the outgoing queries?*" - and you'd partially be right...*however*:

1. WireGuard needs a hostname or IP to connect to.  The author's IP is dynamic - so Dynamic DNS is in use to update a known hostname for WireGuard to connect to
2. WireGuard needs access to (plain old) DNS to lookup the hostname, which it *must* do before it can connect.  
3. The only way to set DNS in Android is either)
-- in WiFi settings ('standard' DNS only, i.e. *not* encrypted) or
-- use Private DNS
4. "Private DNS" on Android has 3 options - "Off", "Automatic" or a user provided hostname can be forced
-- If "Off" is set, plaintext DNS will be used
-- If "Automatic" is used, Android  will connect to a user provided hostname (if provided) or any it can 'find' (which may not be yours, i.e. Google or QuadDNS) - even if WireGuard later overrides it
-- If you force a user provided hostname, Android will ONLY use secure DNS to lookup WireGuard
7. Thus you *ideally* need to provide a secure DNS server for your initial connection. You *could* use an external service, but...
-- that wouldn't be *yours*
-- it would skip your piHole etc...and...
8. You *certainly* don't want any secure DNS server you provide to be publically available but....
9. Your roaming (cellular device) IP will change frequently - so you can't firewall it to check clients before WireGuard has connected
10. Even once WireGuard connects, "Private DNS" will still be used - so it needs to be resolvable/accessible internally *and* externally
11. piHole doesn't offer DoT, so you can't just point at a piHole IP...(even if you could, it doesn't authenticate you...)

## The solution

*diab*.

diab exists to **securely** front **all** your internal *and* external DNS needs - in conjunction with (*ideally*) piHole and Traefik.

Running as a Docker container on a macvlan interface (i.e. with it's own LAN IP) it will provide:

1) Standard (plaintext) DNS - *internally only* - forwarded to a DNS service of your choice
2) DoH - internally *and* externally - forwarded to a DNS service of your choice
3) DoT - internally *and* externally - forwarded to a DNS service of your choice (enabling "Private DNS" on Android)
4) EDNS manipulation (passthrough to an upstream server, or not...)

The assumption here is that the "DNS service of your choice" is already configured (i.e. piHole, or another DoT/DoH/DNSCrypt proxy to an external DNS). *diab* will just continue plugging into that - so all you need to do is change your DNS IP/host to the new *diab* IP.  If you're using piHole *as* your DNS - don't worry, we cover that further down...

Whilst *diab* will be externally available (via DoT, if you want "Private DNS" and/or DoH) - it will *only* respond to queries it is allowed to.  It will reject *external* queries for anything else it's not setup to answer - so whilst it's not "firewalled", it's not useful to anyone else.  

By default, it will allow Android mobile devices to resolve *client1-5.google.com* and *connectivitycheck.gstatic.com* - to prevent any device using it for Private DNS from displaying "offline" or "no internet" alerts, which you don't want when booting up.

Over and above that, you can allow then certain addresses on your domain to respond - i.e. WireGuard.

So - let's run the above example through:
1. Your mobile device is configured to use Wireguard, "Always On" and "Block Connections without VPN"
2. Your mobile device is set to use your Private DNS - using diab.
3. Your mobile device boots up, away from home (using 3G/4G/5G cellular connectivity) and uses the operator DNS to resolve your Private DNS server (plaintext)
4. Your WireGuard client then requests to resolve it's hostname, via Private DNS
5. *diab* sees an *external* (untrusted) request, but it's for your wireguard hostname, which is allowed, so it returns it
6. WireGuard is able to connect
7. WireGuard is told to use your (internal) diab IP address for DNS
8. *diab* now sees all queries (from WireGuard) as *internal*, and therefore trusted
9. If your mobile attempts a connectivity check before WireGuard comes up, *diab* allows those (so you get no errors)
10. If anyone does find your IP responding on DNS/DoH/DoT ports, Traefik filters should silently drop them unless the hostname (SNI) matches
11. If anyone uses the correct SNI will be seen as untrusted, and the queries will fail.

**RECENTLY ADDED :** Addition of routeDNS within *diab* to enable connection **to** DoH or DoT servers (via routedns)<br/>
**RECENTLY ADDED :** EDNS configurability<br/>
**COMING SOON :** Switching failover - currently *diab* will talk to the FIRST server ONLY unless it's down, then the second.  This will be optional in future)

# Configuration

## Volumes

* `/your/ssl/folder:/ssl:ro` (**needed** for DoH and/or DoT - if enabled, it **must** contain *cert.pem* and *key.pem*)
* `/your/dnsdist/config/folder:/etc/dnsdist` (optional - see below)
* `/your/routedns/config/folder:/etc/routedns` (optional - see below)
* `/etc/localtime:/etc/localtime:ro` (optional *but* ensures correct timestamps)
* `/etc/timezone:/etc/timezone:ro` (optional *but* ensures correct timestamps)

**Note** : If you don't create bind mounts for /etc/dnsdist and /etc/routedns, your configuration will not persist container recreation.  If *diab* doesn't find existing configuration files on startup, it will (re)create the necessary ones.  If you want to 'tweak' your setup once *diab* has got you going, mounted configs are the way to go.

## Environment

* **DIAB_CHECKINTERVAL** - Set this to a numberic value in *seconds* (i.e. 60) - where dnsdist will poll for your DIAB_UPSTREAM_IP_AND_PORT (default is **1**). This can help reduce downstream log buildup, but may increase failover time.
* **DIAB_ENABLE_CLI** - Set this to **1** to enable CLI access.  This will enable CLI access from *within* the container using *dnsdist -c -C /etc/dnsdist/dnsdist.conf*
* **DIAB_ENABLE_DNS** - Set this to **1** to enable "normal" DNS.  It will run on 0.0.0.0:53
* **DIAB_ENABLE_DOT** - Set this to **1** to enable DoT. It will run on 0.0.0.0:853 - and **requires** /ssl/cert.pem and /ssl/key.pem to be available via the /ssl bind mount volume above.
* **DIAB_ENABLE_DOH** - Set this to **1** to enable DoT. It will run on 0.0.0.0:443 - and **requires** /ssl/cert.pem and /ssl/key.pem to be available via the /ssl bind mount volume above.
** It will *also* enable an "insecure" DOH server on 0.0.0.0:8053 - which you can use with Traefik, nginx or HAproxy (see below)
* **DIAB_ENABLE_INBOUND_PRIVACY** - Set this to **1** to prevent *diab* passing EDNS info to your UPSTREAM servers (i.e. piHole).  If you are using piHole and want client identification to work, you need to set this to 0, or just not set it (default is **0**)
* **DIAB_ENABLE_OUTBOUND_PRIVACY** - Set this to **1** to prevent *diab* passing EDNS info to any UPSTREAM DoH/DoT servers (via routedns) (default is **0**)
* **DIAB_ALLOWED_EXTERNALLY** - Set this to a comma separated list of hostnames you want untrusted hosts to be able to resolve.  **One should be your WireGuard hostname** (i.e. *vpn.yoursubdomain.yourdomain.com*)
* **DIAB_ENABLE_LOGGING** - Set this to **1** to enable textual messages in the Docker logs/stdout
* **DIAB_ENABLE_ADVANCED_LOGGING** - Set this to **1** to enable verbose messaging from dnsdist itself
* **DIAB_ENABLE_WEBSERVER** - Set this to **1** to enable the dnsdist webserver.  It will run on 0.0.0.0:8083
* **DIAB_TRUSTED_LANS** - Set this to a comma separated list of netmasks you wish to allow, (i.e. *192.168.1.0/24,172.17.0.0/16*)
* **DIAB_UPSTREAM_IP_AND_PORT** - Set this to a comma separated list of IPs and ports of your chosen DNS server (i.e. *1.2.3.4:53*)
* **DIAB_UPSTREAM_NAME** - Set this to a comma spearated list of friendly names for your chosen DNS servers (i.e. *piHole*) - they will show in the web interface and logs
* **DIAB_WEB_PASSWORD** - Set to whatever you want your webserver password to be.  The username can be anything.
* **DIAB_WEB_APIKEY** - Set to whatever you want to use as your dnsdist web API key.  *diab* will generate one for you if not supplied

## Network Requirements

It is **highly** recommended you run the container either on a macvlan interface with it's own IP *or* in host mode (assuming your host is not running DNS and/or HTTPs already).  If you choose to run in bridge mode, *you* will need to handle all port forwarding yourself, and DoT/DoH may fail - and **no support will be offered**.

## DNS Records

### External

You should create a CNAME record (i.e. *dns.yoursubdomain.yourdomain.com*) and point it to either:
- the dynamic DNS hostname you use to point to your dynamic host IP
- the static IP of your host (if you are lucky enough to have a static IP!)

### Internal

Setup a local DNS entry which matches the external *hostname* but point it to the macvlan LAN IP address of the container.  The author uses piHole to provide local DNS entries.

## DoT (Port Forward)

On your router, forward all TCP port 853 traffic to the macvlan LAN IP address of the **container**.

## DoH (Port Forward)

### *Without* Traefik (assumes you have no other HTTPS/port 443 services)

On your router, forward all TCP port 443 traffic to the macvlan LAN IP address of the **container**.

### *With* Traefik

On your router, forward all TCP port 443 traffic to the macvlan LAN IP address of your *Traefik* container.  If you have Traefik running, you are probably already doing this anyway.

### Traefik Configuration (via Container Labels)

* **traefik.enable**=true
* **traefik.http.routers.doh.entryPoints**=websecure (or whatever your https entrypoint is called)
* **traefik.http.routers.doh.middlewares**=mw_doh
* **traefik.http.routers.doh.rule**=HostHeader(\`dns.yoursubdomain.yourdomain.com\`)
* **traefik.http.routers.doh.service**=doh
* **traefik.http.routers.doh.tls**=true
* **traefik.http.routers.doh.tls.certresolver**=your_traefik_cert_provider
* **traefik.http.routers.doh.tls.domains[0].sans**=*.yoursubdomain.yourdomain.com
* **traefik.http.services.doh.loadbalancer.server.port**=8053
* **traefik.http.middlewares.mw_doh.headers.hostsProxyHeaders**=X-Forwarded-For

### Traefik Configuration (via Static Config)

To ensure *diab* sees the correct external IP of a client, you may need to update your Traefik https/websecure entrypoint to allow the use of host header.  Assuming your Traefik configuration is in TOML and your entrypoint is called *websecure* you should update it to look like the following:

`[entryPoints.websecure]`<br/>
` address = ":443"`<br/>
` [entryPoints.websecure.forwardedHeaders]`<br/>
`  insecure=true`<br/>
    
You will then need to restart Traefik, via `docker restart traefik`<br/>
*diab* is already configured to handle X-Forwarded-For headers, but it will ***only*** function if the above is enabled in Traefik.
NB : You can do similar reverse proxying with nginx or HAProxy - but that type of setup is [documented elsewhere](https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy/)!

## WireGuard client config

If you're already running WireGuard, there is little to change - except you should consider changing the client DNS config to the *diab* macvlan IP address.  That way WireGuard can do a secure lookup of it's server IP (via Private DNS) and then continue using *diab* as a server.

You should note here, however, that (by default) WireGuard runs source NAT (SNAT) - and *diab* will only see the IP of the WireGuard container/host.  However, that IP should (one assumes) be part of the *DIAB_TRUSTED_LANS* environment variables.  If not, you'll need to add the WireGuard host IP to the *DIAB_TRUSTED_LANS* as a /32.

## Optional piHole config

### Splitting DNS and DHCP in piHole

If you currently use piHole for DHCP, all your DHCP clients are *probably* using piHole for DNS.  You can leave them there, or you can use piHole's dnsmasq config to use another DNS server (i.e. *diab*) and *diab* can loop back via piHole.  Assuming you have a bind mounted volume for piHole dnsmasq config, you can just create a file in that folder called *03-pihole-dns-override.conf* and put this one line within it:<br/>
`dhcp-option=6,1.2.3.4`<br/>
...where 1.2.3.4 is your *diab* macvlan IP.  Then just issue a:<br/>
`docker restart pihole`<br/>
...and that should be that.

### Identifying clients
If you are using piHole *and* have done the above, you *may* find that it only "sees" (or reports) the macvlan IP of the *diab* host when handling queries.  This can skew your stats, and/or stop it's ability to process Groups etc accordingly.

*diab* supports clients providing EDNS information - which piHole (FTL 5.3.1 and higher) support.  Please check your piHole FTL version (at the bottom of each piHole admin interface page) - if it's >= 5.3.1, then EDNS is **already** enabled by default.<br/>

If you have an older version, then only the dev branches supports EDNS so you'll need to take some steps to enable this in piHole.  To do that, you'll need to do something like this:

`docker exec -it pihole /bin/bash`<br/>
`pihole checkout ftl new/edns0`

Assuming your pihole container is called pihole, the above will get you to a pihole container shell and then pull the EDNS branch, which will restart pihole.  From then on, you should find pihole sees the calling client IP that is talking to *diab*, and not the *diab* macvlan IP.  Again, if your FTL version is >= 5.3.1, it should "just work".

# Usage

## Docker Image/Container operation

If you have not used dnsdist or *diab* before, it is advisable you
- set your required environment variables (per the above)-
- ensure /ssl can be mounted to the container
- ideally ensure /etc/dnsdist and /etc/routedns are bind mounts to give you persistent configuration
- start your container!

Once configured and started, *diab* will check for the existence of /etc/dnsdist/dnsdist.conf<br/>
If the file does **not** exist, it will be created, but **only within the running container** (see below).<br/>
If the file **does** exist (i.e. from a bind mounted volume, or a restarted container) it will be used (most environment variables will be ignored - see below).<br/>

The **only** environment variable that operates outside of the configuration is *DIAB_ENABLE_ADVANCED_LOGGING* - which controls dnsdist verbose logging (set it to **1** to enable it).

If you have a bind mounted volume containing dnsdist.conf and wish to change config, you will have to either:
- edit that file and restart the container<br>
or <br/>
- remove the file and allow the container to build one itself

If you didn't create bind mounts for /etc/dnsdist, but are happy with your running configuration, you can copy it out of the container to a local folder thus:<br/>

`cd /your/desired/host/folder`<br/>
`docker cp containername:/etc/dnsdist/dnsdist.conf ./dnsdist.conf`

You can then put that file in a bind mount for /etc/dnsdist and the container will use it on startup.

# Routing

If you followed the above setup, you should basically be able to envisage the following:

## External client (Request for an ADDRESS from a client *NOT* within *DIAB_TRUSTED_LANS*)

Mobile Device -> DoT Query 853 -> Your Router -> Port Forward 853 -> *diab* DoT Secure 853 -> PROCESS<br/>
Mobile Device -> DoH Query 443 -> Your Router -> Port Forward 443 -> Traefik -> *diab* DoT Insecure 8053 -> PROCESS<br/>
or<br/>
Mobile Device -> DoH Query 443 -> Your Router -> Port Forward 443 -> *diab* DoH 443 -> PROCESS<br/>

...where PROCESS = Allow or Reject<br/>
**NOTE:** Any request for an ADDRESS **NOT** within *DIAB_ALLOWED_EXTERNALLY* will be **rejected**.<br/>

If you are using *diab* for it's initial use case, this would mean your mobile device on 4G with Private DNS on would resolve your hostname and connect via DoT to resolve your Wireguard hostname.  As that hostname is allowed externally, it would resolve, enabling Wireguard to connect.  At that point your device would gain an internal (Wireguard) IP which should be on your Trusted LAN IPs, and everything else resolves - per the below...

## Internal client (Request for an ADDRESS from a client WITHIN *DIAB_TRUSTED_LANS*)

Device -> DNS Query 53 -> *diab* DNS port 53 -> Allow<br/>
Device -> DoT Query 853 -> *diab* DoT port 853 -> Allow<br/>
Device -> DoH Query 443 -> *diab* DoT port 443 -> Allow<br/>

## Onward resolution (*diab* to the outside)

*diab* will resolve from the servers specified in **DIAB_UPSTREAM_IP_AND_PORT**, in the order specified.
If a remote DoH or DoT server was specified, routedns is used to create an internal 'bridge' between dnsdist and the DoH and DoT server.
