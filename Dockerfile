# Base image (CHANGE TO BUSTER FROM LATEST)
FROM bitnami/minideb:latest as dnsdistbuild
# Baseline the image to current standard
RUN apt update -y && apt upgrade -y
# Create and switch into base folder
# RUN mkdir -p /usr/src
WORKDIR /tmp
# Get wget and bzip2 so we can grab and unzip the 1.5 binary
RUN apt-get install -y wget bzip2 && wget https://downloads.powerdns.com/releases/dnsdist-1.6.0-alpha3.tar.bz2 && \
        wget https://golang.org/dl/go1.15.4.linux-amd64.tar.gz && \
        bzip2 -d dnsdist*.bz2 && tar -xvf dnsdist*.tar && rm dnsdist*.tar && \
        gunzip go1.15.4.linux-amd64.tar.gz && tar -xvf go1.15.4.linux-amd64.tar && rm go1.15.4.linux-amd64.tar
# Install all required libraries (quite a few!)
RUN apt-get install -y libboost-dev lua5.3 libedit-dev libsodium-dev ragel libtool gcc g++ make libprotobuf-dev libre2-dev pkg-config liblua5.3-dev libssl-dev libh2o-dev libh2o-evloop-dev libfstrm-dev libsnmp-dev liblmdb++-dev libprotobuf-c-dev protobuf-compiler libsnmp-dev libcdb-dev golang 
# Build ROUTEDNS (to be used for egress capabilities)
RUN GO111MODULE=on /tmp/go/bin/go get -v github.com/folbricht/routedns/cmd/routedns && chown -R root:root ./go
# Build (statically) with DNSCrypt, DoT, DoH support, plus dnstab, protobuf, re2, SNMP and some sanitisation
WORKDIR /tmp/dnsdist-1.6.0-alpha3
# --enable-asan --enable-lsan --enable-ubsan
RUN ./configure --enable-dnscrypt --enable-static --enable-dns-over-tls --enable-dns-over-https --enable-dnstap --with-protobuf --with-re2 --with-net-snmp
# Compile!
RUN make install
# RUN rm -rf /tmp/dnsdist-1.5.0
# RUN apt-get remove -y libboost-dev lua5.3 libedit-dev libsodium-dev ragel libtool libprotobuf-dev libre2-dev pkg-config liblua5.3-dev libssl-dev libh2o-dev libh2o-evloop-dev libfstrm-dev libsnmp-dev liblmdb++-dev libprotobuf-c-dev protobuf-compiler libsnmp-dev libcdb-dev
WORKDIR /

# CHANGE TO BUSTER FROM LATEST
FROM bitnami/minideb:latest
# COPY BINARIES FROM THE BUILD IMAGE
COPY --from=dnsdistbuild /usr/local/bin/dnsdist /usr/local/bin/dnsdist
COPY --from=dnsdistbuild /root/go/bin/routedns /usr/local/bin/routedns
# libasan5 libubsan1 / liblsan0
RUN apt-get update -y && apt-get upgrade -y && apt-get install -y apt-utils liblua5.3-0 libedit2 libsodium23 libfstrm0 libsnmp30 libcdb1 libre2-5 liblmdb0 libh2o-evloop0.13 libprotobuf-dev dnscrypt-proxy curl jq ca-certificates 
COPY ./scripts/diab_confbuild.sh /usr/sbin/diab_confbuild.sh
COPY ./scripts/diab_startup.sh /usr/sbin/diab_startup.sh
COPY ./scripts/diab_healthcheck.sh /usr/sbin/diab_healthcheck.sh
COPY ./scripts/diab_health_script.sh /usr/sbin/diab_health_script.sh
COPY ./scripts/diab_health_json.sh /usr/sbin/diab_health_json.sh
COPY ./scripts/diab_rescue /usr/sbin/diab_rescue
COPY ./scripts/diab_cli /usr/sbin/diab_cli
RUN chmod a+rx /usr/sbin/diab*
HEALTHCHECK  --interval=5m --timeout=3s \
        CMD /usr/sbin/diab_healthcheck.sh
CMD ["/usr/sbin/diab_startup.sh"]
ENTRYPOINT [""]
