# Base image (CHANGE TO BUSTER FROM LATEST)
FROM bitnami/minideb:latest as dnsdistbuild
# Baseline the image to current standard
RUN apt update && apt upgrade
# Create and switch into base folder
# RUN mkdir -p /usr/src
WORKDIR /tmp
# Get wget and bzip2 so we can grab and unzip the 1.5 binary
RUN apt-get install -y wget bzip2 && wget https://downloads.powerdns.com/releases/dnsdist-1.6.0-alpha1.tar.bz2 && \
        wget https://golang.org/dl/go1.15.4.linux-amd64.tar.gz && \
        bzip2 -d dnsdist*.bz2 && tar -xvf dnsdist*.tar && rm dnsdist*.tar && \
        gunzip go1.15.4.linux-amd64.tar.gz && tar -xvf go1.15.4.linux-amd64.tar && rm go1.15.4.linux-amd64.tar
# Install all required libraries (quite a few!)
RUN apt-get install -y libboost-dev lua5.3 libedit-dev libsodium-dev ragel libtool gcc g++ make libprotobuf-dev libre2-dev pkg-config liblua5.3-dev libssl-dev libh2o-dev libh2o-evloop-dev libfstrm-dev libsnmp-dev liblmdb++-dev libprotobuf-c-dev protobuf-compiler libsnmp-dev libcdb-dev golang
# Build ROUTEDNS (to be used for egress capabilities)
RUN GO111MODULE=on /tmp/go/bin/go get -v github.com/folbricht/routedns/cmd/routedns && chown -R root:root ./go
# Build (statically) with DNSCrypt, DoT, DoH support, plus dnstab, protobuf, re2, SNMP and some sanitisation
WORKDIR /tmp/dnsdist-1.6.0-alpha1
# --enable-asan
RUN ./configure  --enable-dnscrypt --enable-static --enable-dns-over-tls --enable-dns-over-https --enable-dnstap --enable-lsan --enable-ubsan --with-protobuf --with-re2 --with-net-snmp
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
RUN echo 199.232.58.132          deb.debian.org >> /etc/hosts
RUN cat /etc/resolv.conf
RUN cat /etc/hosts
RUN apt-get update && apt-get upgrade && apt-get install -y apt-utils libasan5 liblua5.3-0 libedit2 libsodium23 libfstrm0 libsnmp30 libcdb1 libre2-5 liblmdb0 libh2o-evloop0.13 libprotobuf-dev libubsan1 ca-certificates
COPY ./scripts/diab_confbuild.sh /usr/sbin/diab_confbuild.sh
COPY ./scripts/diab_startup.sh /usr/sbin/diab_startup.sh
RUN chmod a+rx /usr/sbin/*.sh
CMD ["/usr/sbin/diab_startup.sh"]
ENTRYPOINT [""]
