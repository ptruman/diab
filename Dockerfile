# Base image (CHANGE TO BUSTER FROM LATEST)
FROM bitnami/minideb:latest as dnsdistbuild
# Baseline the image to current standard
RUN apt update && apt upgrade
# Create and switch into base folder
# RUN mkdir -p /usr/src
WORKDIR /tmp
# Get wget and bzip2 so we can grab and unzip the 1.5 binary
RUN apt-get install -y wget bzip2 && wget https://downloads.powerdns.com/releases/dnsdist-1.5.0.tar.bz2 && \
        bzip2 -d dnsdist*.bz2 && tar -xvf dnsdist*.tar && rm dnsdist*.tar
# WORKDIR /usr/src/dnsdist-1.5.0
# Install all required libraries (quite a few!)
RUN apt-get install -y libboost-dev lua5.3 libedit-dev libsodium-dev ragel libtool gcc g++ make libprotobuf-dev libre2-dev pkg-config liblua5.3-dev libssl-dev libh2o-dev libh2o-evloop-dev libfstrm-dev libsnmp-dev liblmdb++-dev libprotobuf-c-dev protobuf-compiler libsnmp-dev libcdb-dev
# Build (statically) with DNSCrypt, DoT, DoH support, plus dnstab, protobuf, re2, SNMP and some sanitisation
WORKDIR /tmp/dnsdist-1.5.0
RUN ./configure  --enable-dnscrypt --enable-static --enable-dns-over-tls --enable-dns-over-https --enable-dnstap  --enable-asan --enable-lsan --enable-ubsan --with-protobuf --with-re2 --with-net-snmp
# Compile!
RUN make install
# RUN rm -rf /tmp/dnsdist-1.5.0
# RUN apt-get remove -y libboost-dev lua5.3 libedit-dev libsodium-dev ragel libtool libprotobuf-dev libre2-dev pkg-config liblua5.3-dev libssl-dev libh2o-dev libh2o-evloop-dev libfstrm-dev libsnmp-dev liblmdb++-dev libprotobuf-c-dev protobuf-compiler libsnmp-dev libcdb-dev
WORKDIR /

# CHANGE TO BUSTER FROM LATEST
FROM bitnami/minideb:latest
COPY --from=dnsdistbuild /usr/local/bin/dnsdist /usr/local/bin/dnsdist
RUN apt-get update && apt-get upgrade && apt-get install -y apt-utils libasan5 liblua5.3-0 libedit2 libsodium23 libfstrm0 libsnmp30 libcdb1 libre2-5 liblmdb0 libh2o-evloop0.13 libprotobuf-dev libubsan1
COPY ./scripts/diab_confbuild.sh /usr/sbin/diab_confbuild.sh
COPY ./scripts/diab_startup.sh /usr/sbin/diab_startup.sh
RUN chmod a+rx /usr/sbin/*.sh
CMD ["/usr/sbin/diab_startup.sh"]
ENTRYPOINT [""]
