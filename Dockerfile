FROM debian:stable-slim as berkeleydb

ENV BERKELEYDB_VERSION=db-4.8.30.NC
ENV BERKELEYDB_PREFIX=/opt/${BERKELEYDB_VERSION}

RUN apt-get update -y \
    && apt-get install -y curl gcc g++ make autoconf automake libtool

RUN curl https://download.oracle.com/berkeley-db/${BERKELEYDB_VERSION}.tar.gz --output ${BERKELEYDB_VERSION}.tar.gz
RUN tar -xzf *.tar.gz
RUN sed s/__atomic_compare_exchange/__atomic_compare_exchange_db/g -i ${BERKELEYDB_VERSION}/dbinc/atomic.h
RUN mkdir -p ${BERKELEYDB_PREFIX}

WORKDIR /${BERKELEYDB_VERSION}/build_unix

RUN ../dist/configure --enable-cxx --disable-shared --with-pic --prefix=${BERKELEYDB_PREFIX} --build=arm-linux
RUN make -j$(nproc --ignore=4)
RUN make install
RUN rm -rf ${BERKELEYDB_PREFIX}/docs

FROM debian:stable-slim as builder

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
RUN apt-get update -y \
    && apt-get install -y curl gcc g++ make autoconf automake libtool \
      git pkg-config libboost-all-dev libssl-dev libevent-dev libzmq3-dev libfmt-dev

### checkout latest _RELEASE_ so we will build stable
### (we do not want to build working master for production)
RUN git clone --depth 1 -c advice.detachedHead=false \
    -b ${SOURCE_VERSION:-$(basename $(curl -Ls -o /dev/null -w %{url_effective} ${SOURCE_REPO}/releases/latest))} \
    ${SOURCE_REPO}.git ${BLOCKCHAIN_NAME}

### Dump build envs to build_info dir
RUN mkdir -p build_info && printenv | tee build_info/build_envs.txt

### Save git commit sha of the repo to build_info dir
RUN cd ${BLOCKCHAIN_NAME} && echo "SOURCE_SHA=$(git rev-parse HEAD)" | tee -a ../build_info/build_envs.txt

### Configure sources
RUN cd ${BLOCKCHAIN_NAME} \
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
    && make -j$(nproc --ignore=4) \
    && make install

RUN find /opt

RUN strip ${BUILD_PREFIX}/bin/litecoin-cli \
    && strip ${BUILD_PREFIX}/bin/litecoin-tx \
    && strip ${BUILD_PREFIX}/bin/litecoind \
    && strip ${BUILD_PREFIX}/lib/libbitcoinconsensus.a \
    && strip ${BUILD_PREFIX}/lib/libbitcoinconsensus.so.0.0.0

### Output any missing library deps:
RUN { for i in $(find /opt -type f -executable -print); \
    do readelf -d $i 2>/dev/null | grep NEEDED | awk '{print $5}' | sed "s/\[//g" | sed "s/\]//g"; done; } | sort -u

FROM debian:stable-slim

### https://specs.opencontainers.org/image-spec/annotations/
LABEL org.opencontainers.image.title="Litecoin Node Docker Image"
LABEL org.opencontainers.image.vendor="Xorde Technologies"
LABEL org.opencontainers.image.source="https://github.com/xorde-labs/docker-litecoin-node"

ENV BLOCKCHAIN_NAME=litecoin
ARG DOCKER_GIT_SHA

### Add user and set home directory
RUN useradd -m -s /sbin/nologin -d /home/${BLOCKCHAIN_NAME} ${BLOCKCHAIN_NAME}
WORKDIR /home/${BLOCKCHAIN_NAME}

### Add packages
RUN apt-get update -y \
    && apt-get install -y curl libfmt7 libzmq5 libboost-filesystem1.74.0 libboost-thread1.74.0 libevent-2.1-7 libevent-pthreads-2.1-7

### Copy script files (entrypoint, config, etc)
COPY ./scripts .
RUN chmod 755 ./*.sh && ls -adl ./*.sh

### Copy build result from builder context
COPY --from=builder /opt /opt
COPY --from=builder /workdir/build_info/ .

ENV PATH=/opt/${BLOCKCHAIN_NAME}/bin:$PATH

### Output build binary deps to check if it is compiled static (or else missing some libraries):
RUN find /opt -type f -exec sha256sum {} \; \
    && ldd /opt/litecoin/bin/litecoind \
    && echo "Built version: $(./version.sh)"

RUN mkdir -p .${BLOCKCHAIN_NAME} \
    && chown -R ${BLOCKCHAIN_NAME} .

USER ${BLOCKCHAIN_NAME}

ENTRYPOINT ["./entrypoint.sh"]

EXPOSE 9332 9333 19332 19333 19444