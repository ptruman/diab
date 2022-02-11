# diab V2.0 Dockerfile
# 
# Create the temporary "dnsdistbuild" image to generate required binaries
# Set base image (NB: There may be potential switch to "buster" from "latest" - TBC)
FROM bitnami/minideb:latest as dnsdistbuild
# Baseline the image to latest default packages
RUN apt update -y && apt upgrade -y
# Switch into /tmp
WORKDIR /tmp
# Get wget, bzip2, dnsdist-1.6 src & golang - then unzip & untar everything...
RUN apt-get install -y wget bzip2 && wget https://downloads.powerdns.com/releases/dnsdist-1.6.0.tar.bz2 && \
        wget https://golang.org/dl/go1.15.4.linux-amd64.tar.gz && \
        bzip2 -d dnsdist*.bz2 && tar -xvf dnsdist*.tar && rm dnsdist*.tar && \
        gunzip go1.15.4.linux-amd64.tar.gz && tar -xvf go1.15.4.linux-amd64.tar && rm go1.15.4.linux-amd64.tar
# Install all required libraries/packages to support the build (quite a few!)
RUN apt-get install -y libboost-dev lua5.3 libedit-dev libsodium-dev ragel libtool gcc g++ make libprotobuf-dev libre2-dev pkg-config liblua5.3-dev libssl-dev libh2o-dev libh2o-evloop-dev libfstrm-dev libsnmp-dev liblmdb++-dev libprotobuf-c-dev protobuf-compiler libsnmp-dev libcdb-dev golang 
# Build routedns (to be used for egress capabilities)
RUN GO111MODULE=on /tmp/go/bin/go get -v github.com/folbricht/routedns/cmd/routedns && chown -R root:root ./go
# Build dnstap binary (to be used if deep logging is required)
RUN GO111MODULE=on /tmp/go/bin/go get -u github.com/dnstap/golang-dnstap/dnstap && chown -R root:root ./go
# Switch into dnsdist src folder
WORKDIR /tmp/dnsdist-1.6.0
# Build (statically) with DNSCrypt, DoT, DoH support, plus dnstab, protobuf, re2, SNMP and some sanitisation
# NB : The following switches were previously enabled, but are now disabled : --enable-asan --enable-lsan --enable-ubsan
RUN ./configure --enable-dnscrypt --enable-static --enable-dns-over-tls --enable-dns-over-https --enable-dnstap --with-protobuf --with-re2 --with-net-snmp
# Compile!
RUN make install
# Switch back to root /
WORKDIR /

# Create the actual "live" image
# Set base image (NB: There may be potential switch to "buster" from "latest" - TBC)
FROM bitnami/minideb:latest
# Copy over the key binaries dnsdist, routedns & dnstap from the dnsdistbuild image above
COPY --from=dnsdistbuild /usr/local/bin/dnsdist /usr/local/bin/dnsdist
COPY --from=dnsdistbuild /root/go/bin/routedns /usr/local/bin/routedns
COPY --from=dnsdistbuild /root/go/bin/dnstap /usr/local/bin/dnstap
# Install all required libraries/packages to support the build (quite a few!)
# NB : The following packages were previously required, but are now disabled : libasan5 libubsan1 / liblsan0
# NB : Enabling the asan/lsan/ubsan packages in dnsdistbuild WILL require these back in.
RUN apt-get update -y && apt-get upgrade -y && apt-get install -y apt-utils liblua5.3-0 libedit2 libsodium23 libfstrm0 libsnmp30 libcdb1 libre2-5 liblmdb0 libh2o-evloop0.13 libprotobuf-dev dnscrypt-proxy curl jq ca-certificates 
# Copy in the diab scripts to /usr/sbin
COPY ./diab_version.txt /etc/dnsdist/diab_version.txt
COPY ./scripts/diab_confbuild.sh /usr/sbin/diab_confbuild.sh
COPY ./scripts/diab_startup.sh /usr/sbin/diab_startup.sh
COPY ./scripts/diab_healthcheck.sh /usr/sbin/diab_healthcheck.sh
COPY ./scripts/diab_health_script.sh /usr/sbin/diab_health_script.sh
COPY ./scripts/diab_health_json.sh /usr/sbin/diab_health_json.sh
COPY ./scripts/diab_forceup.sh /usr/sbin/diab_forceup.sh
COPY ./scripts/diab_rescue /usr/sbin/diab_rescue
COPY ./scripts/diab_cli /usr/sbin/diab_cli
# Set all scripts executable
RUN chmod a+rx /usr/sbin/diab*
# Create the docker healthcheck call to the healthcheck script
HEALTHCHECK  --interval=5m --timeout=3s \
        CMD /usr/sbin/diab_healthcheck.sh
# Setup the default command (entrypoint is blank)
CMD ["/usr/sbin/diab_startup.sh"]
ENTRYPOINT [""]
