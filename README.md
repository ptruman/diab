# diab

Private "**D**NS **I**n **A** **B**ox" - is a lightweight (ish) container designed for to provide secure DNS.
Initially and primarily created for use with piHole and Traefik, it has several potential use cases.

The initial use-case is outlined below and may be surprisingly useful for many.  Read on :)

This container makes use of:
 - the [bitnami/minideb](https://hub.docker.com/r/bitnami/minideb/) image
 - the totally wonderful [dnsdist](https://dnsdist.org) - which provides the DoH, DoT and DNS front end functionality
 - routedns (https://github.com/folbricht/routedns) for DoT and DoH backend support (will be removed in 3.0, as dnsdist 1.7 supports natively)
 - dnscrypt-proxy to enable use of remote DNSCrypt servers (such as OpenDNS)
 - a modified version of orderedLeastOutstanding (https://github.com/sysadminblog/dnsdist-configs/blob/master/orderedLeastOutstanding.lua)
 - dnstap for DNS logging and debugging (https://github.com/dnstap/golang-dnstap)
 - Some of the authors own scripting ([bash](https://www.gnu.org/software/bash/) and [lua](http://www.lua.org/))
 
## Why encrypt DNS?
Normal DNS queries are sent "plaintext" (unencrypted) - meaning anyone or anything (person or code) with access to your traffic can see which sites your devices are requesting.  This could happen on your network between your device and your DNS server, or on the internet, between your device/DNS server and your ISP's server.  Whilst a DNS lookup request in itself may not indicate an actual subsequent connection to a returned address, it's a fairly good bet that a request would probably be followed up by a connection to that address.

DNS-over-HTTPS (DoH) and DNS-over-TLS (DoT) and DNSCrypt have been created to allow encryption of DNS queries so that requests cannot be intercepted and viewed - so only your device(s) and your DNS server of choice know what sites you have requested, until an actual connection is initiated. Traffic inspection can still show IP addresses, although with the declining IPv4 address space and prevalance of virtual hosting, IP addresses are not a guarantee of which sites may be connected to - but TLS handshakes/SNI can still reveal which site is being requested.

Additionally, EDNS can reveal the MAC and/or IP of an originating machine, even to intermediate DNS servers.

DNS encryption, combined with ESNI makes things a bit better, and *diab* is here to assist with the rest....

## The use case

As mentioned, this is quite specific - but is designed to keep as much of 'your' DNS traffic as secure as can be.

The assumption is that you already do (or want to do) the following:
- Run or host your own Linux server 
- Run Docker on said server
- Have an internet connection with a unique (static or dynamic) external IP address
- Have a router with port forwarding capabilities
- Run your own DNS service/filtering (i.e. piHole) - _this is not essential however_
-- If you run your own DNS, you likely don't want devices/browsers on your network going to "other" DNS providers
-- You may *already* have piHole (or other DNS tool) configured to securely talk to another DNS service, i.e. OpenDNS via DNSCrypt
- Run your own VPN (i.e. WireGuard) to secure your mobile device traffic (which means access to your piHole server when roaming!)
-- You want to make use of Android's "Always-On" and "Block connections without VPN" options on your mobile
- *Don't* want to make your DNS/piHole "public" facing (anyone might find/use it!)
- Just make it all look seamless!

If you want to setup your own Linux, OMV, Docker, Traefik and piHole box - read our article [https://site.gothtech.co.uk/articles/omv-portainer-traefik-letsencrypt](here).

If you want to setup WireGuard with the above - read our article [https://site.gothtech.co.uk/articles/omv-portainer-traefik-letsencrypt/wireguard-traefik](here).

### The browser and/or device dilemma

Firefox supports DoH, and (unless you switch it off) it might start using it with DNS servers you can't control (i.e. bypassing **your** DNS).  You can't simply just block port 443 outbound, as you'd block all secure web traffic...thus DoH is a blessing *and* a curse.

Chrome (and Android) support DoT (which uses TCP port 853, thus *can* be blocked more easily) - but *only* if the DNS server specified on the network also offers an *unencrypted* service for an initial connection, which means most people wont get it locally on the same IP as their DNS server, as most DNS servers don't offer plain DNS *and* DoT.

Finally, piHole currently only offers plain old DNS...

### Making sense?

The author had all of the use case requirements described above - a Linux box with OpenMediaVault, Docker with piHole, Traefik and WireGuard - along with a desire to use Android's "Always-On" and "Block connections without VPN" settings - ***but*** ensuring that the "Private DNS" function could be used, but using the author's own server.

You might at this point think "*Hang on, won't WireGuard be encrypting the DNS traffic to piHole, and DNScrypt encrypting all the outgoing queries?*" - and you'd partially be right...*however*:

1. WireGuard needs a hostname or IP to connect to.  The author's public IP is dynamic - so Dynamic DNS is in use to update a known hostname for WireGuard to connect to
2. WireGuard needs access to (plain old) DNS to lookup the hostname, which it *must* do before it can connect.  
3. The only way to set DNS in Android is either:
   - in WiFi settings ('standard' DNS only, i.e. *not* encrypted) or
   - use Private DNS
4. "Private DNS" on Android has 3 options - "Off", "Automatic" (see below) *or* a user provided hostname can be forced
   - If "Off" is set, plaintext DNS will be used
   - If "Automatic" is used, Android will connect to a user provided hostname (if provided) or any it can 'find' (or hardcoded) ***which may not be yours***, i.e. Google or QuadDNS) - even if WireGuard later overrides it
  - If you force a user provided hostname, Android can ONLY use secure DNS to lookup WireGuard

Therefore for full control, you need need to :
- provide an "insecure" (unencrypted) DNS server for Android's _initial_ connection
- ensure the same DNS server can also speak DoT
- You could opt to use a provided services to do this, *however*:
  - it wouldn't be *yours*
  - it wouldn't be able to use your piHole etc...

And lastly, if you're going to have to run your own, *public facing, unencrypted* DNS server to support your mobile devices:
- You *certainly* don't want any secure DNS server you provide to be publically available but....
- Your roaming (cellular device) IP will change *frequently* - so you ***can't*** firewall it to check clients *before* WireGuard has connected-
- Even once WireGuard connects, "Private DNS" will still be used - so it needs to be resolvable/accessible both internally *and* externally
- piHole doesn't offer DoT, so you can't just point at a piHole IP...(even if you could, it doesn't authenticate you...)

## The solution?

*diab*.

*diab* exists to **securely** front **all** your internal *and* external DNS needs - in conjunction with (*ideally*) piHole and Traefik.

Running as a Docker container on a macvlan interface (i.e. with it's own LAN IP) it will provide:

1. Standard (plaintext) DNS - *internally only* - forwarded to a DNS service of your choice (i.e. piHole)
   - It can (and should) be configured to answer specific external queries, just to get your WireGuard/VPN connected
3. DoH - internally *and* externally - forwarded to a DNS service of your choice
4. DoT - internally *and* externally - forwarded to a DNS service of your choice (enabling "Private DNS" on Android)
5. DNSCrypt outbound support - enabling a service of your choice (such as OpenDNS)
6. EDNS manipulation (passthrough to an upstream server, or not...)

Not only that, but *diab* can be "looped" - so for example, the author:
- Runs *diab*, listening on DoH & DoT
- *diab* is configured to speak to piHole **and** OpenDNS, via DNSCrypt (in failover)
- piHole is configured to use the *diab* OpenDNS connection

Thus, the author gets encrypted connections, piHole filtering, and encrypted internet lookups.  If piHole fails, *diab* simply fails over and continues using OpenDNS securely.

The assumption here is that you are already using your "DNS service of choice" (i.e. piHole, or another DoT/DoH/DNSCrypt proxy to an external DNS). *diab* can just continue plugging into that - providing you a secure front end - so all you need to do is tell *diab* where your existing DNS setup is and change your network DNS to the new *diab* IP.  

*diab* can be externally available (via DoT, if you want "Private DNS" and/or DoH) - but it will *only* respond to queries it is allowed to (unless you tell it otherwise).  It will reject **all** *external* queries for anything else it's not setup to answer - so whilst it's not "firewalled", it's not useful to anyone else.  It also has rate limiting enabled by default.

That said, by default, it *will* allow Android mobile devices to resolve *client1-5.google.com* and *connectivitycheck.gstatic.com* - to stop any device using it for Private DNS from displaying "offline" or "no internet" alerts, which you don't want when booting up :)

Ultimately, you only need to let it publically answer requests for your VPN server, i.e. WireGuard.

So - let's run the above example through:
1. Your mobile device is configured to use Wireguard, "Always On" and "Block Connections without VPN"
2. Your mobile device is set to use your Private DNS - using *diab*.
3. Your mobile device boots up, away from home (using 3G/4G/5G cellular connectivity) and uses the operator's (plaintext) DNS to resolve the IP of your Private DNS server 
4. WireGuard will attempt connection to it's hostname (which should point to your public IP)
5. Android will attempt to lookup the WireGuard hostname via Private DNS
6. *diab* sees an *external* (untrusted) request, but it's for your WireGuard hostname, which is allowed, so it answers
7. WireGuard connects to your external IP
8. WireGuard config should then use your (internal, LAN) *diab* IP address for DNS (i.e. *diab*)
9. *diab* now sees all queries (from the WireGuard interface) as *internal*, and therefore trusted
10. If your mobile attempts a connectivity check before WireGuard comes up, *diab* allows those (so you get no errors)
11. If anyone does find your IP responding on DNS/DoH/DoT ports, Traefik filters should silently drop them unless the hostname (SNI) matches
12. If anyone uses the correct SNI will be seen as untrusted, and the queries will fail.

# Configuration

## Volumes

* `/your/ssl/folder:/ssl:ro` (**needed** for DoH and/or DoT - if enabled, it **must** contain *cert.pem* and *key.pem*)
* `/your/dnsdist/config/folder:/etc/dnsdist` (optional - see below)
* `/your/routedns/config/folder:/etc/routedns` (optional - see below)
* `/etc/localtime:/etc/localtime:ro` (optional *but* ensures correct timestamps)
* `/etc/timezone:/etc/timezone:ro` (optional *but* ensures correct timestamps)

**Note** : If you don't create bind mounts for /etc/dnsdist and /etc/routedns, your configuration will not persist container recreation.  If *diab* doesn't find existing configuration files on startup, it will (re)create the necessary ones.  If you want to 'tweak' your setup once *diab* has got you going, mounted configs are the way to go.

## Environment

* **DIAB_CHECKINTERVAL** - Set this to a numberic value in *seconds* (i.e. 60) - where dnsdist will poll for your DIAB_UPSTREAM_IP_AND_PORT (default is **1**). This can help reduce downstream log buildup, but may *increase* failover time.
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
* **DIAB_UPSTREAM_IP_AND_PORT** - Set this to a comma separated list of IPs and ports of your chosen DNS server (i.e. *1.2.3.4:53,2.3.4.5:53*)
* **DIAB_UPSTREAM_NAME** - Set this to a comma spearated list of friendly names for your chosen DNS servers (i.e. *piHole*) - they will show in the web interface and logs
* **DIAB_ENABLE_STRICT_ORDER** - Set this to 1 if you want *diab* to **only** use upstream servers in the order specified (default is **0**)
* **DIAB_OPEN_INTERMEDIATE** - Set this to 1 if you want *diab* to make it's internal ports open to everyone internally (default is **0**)
  * NB : You will need this if you want to point diab -> piHole -> diab DNSCrypt etc.
* **DIAB_WEB_PASSWORD** - Set to whatever you want your webserver password to be.  The username can be anything.  Overridden if you use DIAB_WEB_PASSWORD_FILE.
* **DIAB_WEB_PASSWORD_FILE** - Set this to /var/run/secrets/DIAB_WEB_PASSWORD_FILE if you want to map a Docker secrets file for the web password.
* **DIAB_WEB_APIKEY** - Set to whatever you want to use as your dnsdist web API key.  *diab* will generate one for you if not supplied (the reverse of DIAB_WEB_PASSWORD)
* **DIAB_FORCEREBUILD** - Set this to 1 if you want *diab* to rebuild configuration on every startup
* **DIAB_MAX_QUEUE** - Set this to the number of queued queries you want to allow before *diab* fails to the next server (default is **10**) 
* **DIAB_MAX_DROPS** - Set this to the number of dropped queries you want to allow before *diab* fails to the next server (default is **10**)
* 
## Network Requirements

It is **highly** recommended you run the container either on a macvlan interface with it's own IP *or* in host mode (assuming your host is not running DNS and/or HTTPs already).  If you choose to run in bridge mode, *you* will need to handle all port forwarding yourself, and DoT/DoH may fail - and **no support will be offered**.
That said, you will need to forward ports:
* 53
* 443
* 853
* 8053
* 8083

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
- set your required environment variables (per the above)
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
*or*<br/>
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

*diab* will use the servers specified to create DNS, DoH, DoT or DNSCrypt connections accordingly, thus you *must* specify servers thus:
* DNS : IP:53 (i.e. 8.8.8.8:53)
* DoT : hostname:853 (i.e. your.dns.host.ip:853)
* DoH : https://hostname/dns-query (i.e. the full DoH URL for the service)
* DNSCrypt : sdns://string (where string is the hash provided by the service, or generated via https://dnscrypt.info/stamps/)

## Web Interface

*diab* exposes the dnsdist web interface on port 8083.  There is NO username.  The password is specified in **DIAB_WEB_PASSWORD**

## Command Line Interface

If needs be, the native dnsdist CLI can be accessed from the Docker Shell, by running *diab_cli*
Typing *?* will show all commands available.

The following additional commands are available within the diab host shell:
* _diab_rescue_ : Downloads nano & ps utilities if you want to edit things "on the fly" in the image
* _diab_forceup.sh_ : Forces all resolvers "up" 
* _diab_enable_dnstap_ : Enables DNSTAP logging
* _diab_disable_dnstap_ : Disables DNSTAP logging

# Known Issues

## All resolvers down
diab will sometimes start and mark all configured resolvers as down.  This is obviously a problem.
You can either:

* Access the container CLI and run **diab_forceup.sh** - which will forcibly mark the servers as up.  This may resolve the issue.
* If the above does not work, delete any mounted dnsdist.conf OR access the container CLI and run **diab_confbuild.sh OVERRIDE** - then restart the container.

For some reason, rebuilding the configuration file (even if nothing has changed) seems to coax dnsdist to start correctly.

## Traefik router won't start
Traefik will not add (or start) a router if the container reports 'unhealthy'.
If a server gets marked down, the diab container will mark itself as unhealthy, which may cause the Traefik router to not start, or stop if running.
This can be a problem for DoH services.

If this becomes an issue, consider a direct DNS A/CNAME record to the IP of your diab host to bypass Traefik - or resolve the issues with the remote server.
