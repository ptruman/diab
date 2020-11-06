# Base image
FROM bitnami/minideb:latest
# Baseline the image to current standard
RUN apt update
RUN apt upgrade
# Create and switch into base folder
RUN mkdir -p /usr/src
WORKDIR /usr/src
# Get wget and bzip2 so we can grab and unzip the 1.5 binary
RUN apt-get install -y wget bzip2
# Grab, unzip and untar the 1.5 binary
RUN wget https://downloads.powerdns.com/releases/dnsdist-1.5.0.tar.bz2
RUN bzip2 -d dnsdist*.bz2
RUN tar -xvf dnsdist*.tar
# Tidy up and switch to the source folder
RUN rm dnsdist*.tar
WORKDIR /usr/src/dnsdist-1.5.0
# Install all required libraries (quite a few!)
RUN apt-get install -y libboost-dev lua5.3 libedit-dev libsodium-dev ragel libtool gcc g++ make libprotobuf-dev libre2-dev pkg-config liblua5.3-dev libssl-dev libh2o-dev libh2o-evloop-dev libfstrm-dev libsnmp-dev liblmdb++-dev libprotobuf-c-dev protobuf-compiler libsnmp-dev libcdb-dev
# Build (statically) with DNSCrypt, DoT, DoH support, plus dnstab, protobuf, re2, SNMP and some sanitisation
RUN ./configure  --enable-dnscrypt --enable-static --enable-dns-over-tls --enable-dns-over-https --enable-dnstap  --enable-asan --enable-lsan --enable-ubsan --with-protobuf --with-re2 --with-net-snmp
# Compile!
RUN make install
WORKDIR /usr/src
RUN rm -rf ./dnsdist-1.5.0
CMD ["dnsdist", "-C", "/etc/dnsdist/dnsdist.conf", "--supervised"]
ENTRYPOINT [""]

