FROM alpine:latest as berkeleydb

RUN sed -i 's/http\:\/\/dl-cdn.alpinelinux.org/https\:\/\/alpine.global.ssl.fastly.net/g' /etc/apk/repositories
RUN apk --no-cache add autoconf patch
RUN apk --no-cache add automake
RUN apk --no-cache add build-base
RUN apk --no-cache add libressl

ENV BERKELEYDB_VERSION=db-4.8.30.NC
ENV BERKELEYDB_PREFIX=/opt/${BERKELEYDB_VERSION}

RUN wget https://download.oracle.com/berkeley-db/${BERKELEYDB_VERSION}.tar.gz
RUN tar -xzf *.tar.gz
RUN sed s/__atomic_compare_exchange/__atomic_compare_exchange_db/g -i ${BERKELEYDB_VERSION}/dbinc/atomic.h
RUN mkdir -p ${BERKELEYDB_PREFIX}

WORKDIR /${BERKELEYDB_VERSION}/build_unix

RUN ../dist/configure --enable-cxx --disable-shared --with-pic --prefix=${BERKELEYDB_PREFIX}
RUN make -j4
RUN make install
RUN rm -rf ${BERKELEYDB_PREFIX}/docs

FROM alpine:latest as builder

ENV BLOCKCHAIN_NAME=litecoin
ENV BUILD_PREFIX=/opt/$BLOCKCHAIN_NAME

ARG SOURCE_VERSION
ARG SOURCE_REPO=https://github.com/litecoin-project/litecoin
ARG DOCKER_GIT_SHA

WORKDIR /workdir

### Copy berkeleydb from previous stage
COPY --from=berkeleydb /opt /opt

### Copy builder scripts, patches, etc...
COPY /builder /builder

### Install required dependencies
RUN apk upgrade -U && \
    apk add curl git autoconf automake make gcc g++ clang libtool patch && \
    apk add protobuf-dev libqrencode-dev libevent-dev chrpath zeromq-dev sqlite-dev boost-dev miniupnpc-dev openssl-dev

### Install Berkeley DB 4.8 (required for wallet functionality)
RUN apk add --no-cache wget && \
    curl https://download.oracle.com/berkeley-db/db-4.8.30.NC.tar.gz --output db-4.8.30.NC.tar.gz && \
    tar xzf db-4.8.30.NC.tar.gz && \
    cd db-4.8.30.NC && for i in /builder/patches/bdb4.8/*.patch; do patch -t -p1 -i $i; done && \
    cd build_unix && ../dist/configure --enable-cxx --build=arm-linux --prefix=/usr && \
    make -j$(nproc --ignore=4) && \
    make install

RUN find / | grep libdb_cxx

RUN apk add --no-cache fmt-dev gcompat libstdc++

### checkout latest _RELEASE_ so we will build stable
### (we do not want to build working master for production)
RUN git clone --depth 1 -c advice.detachedHead=false \
    -b ${SOURCE_VERSION:-$(basename $(curl -Ls -o /dev/null -w %{url_effective} ${SOURCE_REPO}/releases/latest))} \
    ${SOURCE_REPO}.git ${BLOCKCHAIN_NAME}

### Dump build envs to build_info dir
RUN mkdir -p build_info && printenv | tee build_info/build_envs.txt

### Save git commit sha of the repo to build_info dir
RUN cd ${BLOCKCHAIN_NAME} && echo "SOURCE_SHA=$(git rev-parse HEAD)" | tee -a ../build_info/build_envs.txt

### Patch sources
RUN cd ${BLOCKCHAIN_NAME} \
    && sed -i '/AC_PREREQ/a\AR_FLAGS=cr' src/univalue/configure.ac \
    && sed -i '/AX_PROG_CC_FOR_BUILD/a\AR_FLAGS=cr' src/secp256k1*/configure.ac \
    && sed -i s:sys/fcntl.h:fcntl.h: src/compat.h

### Configure sources
RUN LD_LIBRARY_PATH=/usr/glibc-compat/lib cd ${BLOCKCHAIN_NAME} \
    && ./autogen.sh \
    && ./configure LDFLAGS=-L`ls -d /opt/db*`/lib/ CPPFLAGS=-I`ls -d /opt/db*`/include/ \
    --prefix=$BUILD_PREFIX \
    --mandir=/usr/share/man \
    --disable-tests \
    --disable-bench \
    --disable-ccache \
    --without-gui \
    --with-utils \
    --with-libs \
    --with-daemon \
    --with-pic \
    --enable-cxx \
    --enable-glibc-back-compat

### Make build
RUN cd ${BLOCKCHAIN_NAME} \
    && make -j$(nproc --ignore=4)

RUN strip ${BUILD_PREFIX}/bin/litecoin-cli
RUN strip ${BUILD_PREFIX}/bin/litecoin-tx
RUN strip ${BUILD_PREFIX}/bin/litecoind
RUN strip ${BUILD_PREFIX}/lib/libbitcoinconsensus.a
RUN strip ${BUILD_PREFIX}/lib/libbitcoinconsensus.so.0.0.0

### Install build
RUN cd ${BLOCKCHAIN_NAME} \
    && mkdir -p /workdir/build \
    && make install DESTDIR=/workdir/build \
    && find /workdir/build

### Output any missing library deps:
RUN { for i in $(find /workdir/build/usr/bin/ -type f -executable -print); \
    do readelf -d $i 2>/dev/null | grep NEEDED | awk '{print $5}' | sed "s/\[//g" | sed "s/\]//g"; done; } | sort -u

FROM alpine:latest

### https://specs.opencontainers.org/image-spec/annotations/
LABEL org.opencontainers.image.title="litecoin Node Docker Image"
LABEL org.opencontainers.image.vendor="Xorde Technologies"
LABEL org.opencontainers.image.source="https://github.com/xorde-labs/docker-litecoin-node"

ENV BLOCKCHAIN_NAME=litecoin
WORKDIR /home/${BLOCKCHAIN_NAME}

### Add packages
RUN apk upgrade -U \
    && apk add openssl ca-certificates boost miniupnpc libevent libzmq libstdc++ libgcc

### Add group
RUN addgroup -S ${BLOCKCHAIN_NAME}

### Add user
RUN adduser -S -D -H -h /home/${BLOCKCHAIN_NAME} \
    -s /sbin/nologin \
    -G ${BLOCKCHAIN_NAME} \
    -g "User of ${BLOCKCHAIN_NAME}" \
    ${BLOCKCHAIN_NAME}

### Copy script files (entrypoint, config, etc)
COPY ./scripts .
RUN chmod 755 ./*.sh && ls -adl ./*.sh

### Copy build result from builder context
COPY --from=builder /workdir/build /
COPY --from=builder /workdir/build_info/ .

### Output build binary deps to check if it is compiled static (or else missing some libraries):
RUN find . -type f -exec sha256sum {} \; \
    && ldd /usr/bin/litecoind \
    && echo "Built version: $(./version.sh)"

RUN mkdir -p .${BLOCKCHAIN_NAME} \
    && chown -R ${BLOCKCHAIN_NAME} .

USER ${BLOCKCHAIN_NAME}

ENTRYPOINT ["./entrypoint.sh"]

EXPOSE 8332 8333