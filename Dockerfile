FROM ubuntu:trusty
MAINTAINER Saifuddin Nair <saifuddin@abyres.net>
# set noninteractive mode
# DUMB-INIT LATEST: https://github.com/Yelp/dumb-init/releases/
# GOSU LATEST:      https://github.com/tianon/gosu/releases/

# explicitly set user/group IDs
RUN groupadd -r postgres --gid=999 && useradd -r -M -d /var/lib/postgresql/data -g postgres --uid=999 postgres

ENV DEBIAN_FRONTEND=noninteractive \
    DUMB_INIT_VERSION=1.0.0 \
    GOSU_VERSION=1.7

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y build-essential software-properties-common curl unzip wget dnsutils ca-certificates && \
    apt-get clean -y && \
    apt-get --purge autoremove -y && \
    rm -rf /tmp/* && \
    rm -rf /var/tmp/* && \
    rm -rf /var/lib/apt/lists/* && \
    wget "https://github.com/Yelp/dumb-init/releases/download/v${DUMB_INIT_VERSION}/dumb-init_${DUMB_INIT_VERSION}_$(dpkg --print-architecture).deb" && \
    dpkg -i "dumb-init_${DUMB_INIT_VERSION}_$(dpkg --print-architecture).deb" && \
    rm "dumb-init_${DUMB_INIT_VERSION}_$(dpkg --print-architecture).deb" && \
    curl -o /usr/local/bin/gosu -fsSL "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-$(dpkg --print-architecture)" && \
    chmod +x /usr/local/bin/gosu && \
    gosu nobody true


ENV POSTGRES_VERSION=9.4

# add keys for psql & pgrouting
RUN wget --quiet -O - http://packages.2ndquadrant.com/bdr/apt/AA7A6805.asc | apt-key add - && \
    echo "deb http://packages.2ndquadrant.com/bdr/apt/ "$(lsb_release -sc)"-2ndquadrant main" >> /etc/apt/sources.list.d/2ndquadrant.list && \
    wget --quiet -O - http://apt.postgresql.org/pub/repos/apt/ACCC4CF8.asc | apt-key add - && \
    echo "deb http://apt.postgresql.org/pub/repos/apt "$(lsb_release -sc)"-pgdg main" >> /etc/apt/sources.list

# make sure UTF8 is used
RUN locale-gen --no-purge en_US.UTF-8
ENV LC_ALL en_US.UTF-8
RUN update-locale LANG=en_US.UTF-8    

# update & install psql 9.4 w/ BDR (-dev package needed for postgis) and postgis dependencies
RUN apt-get update && \
    apt-get install -y postgresql-common &&\
    sed -ri 's/#(create_main_cluster) .*$/\1 = false/' /etc/postgresql-common/createcluster.conf && \
    apt-get install -y -f \
        postgresql-bdr-${POSTGRES_VERSION} \
        postgresql-bdr-client-${POSTGRES_VERSION} \
        postgresql-bdr-contrib-${POSTGRES_VERSION} \
        postgresql-bdr-${POSTGRES_VERSION}-bdr-plugin \
        pgtune && \
    rm -rf /var/lib/apt/lists/*

# make the sample config easier to munge (and "correct by default")
RUN mv -v /usr/share/postgresql/$POSTGRES_VERSION/postgresql.conf.sample /usr/share/postgresql/ && \
    ln -sv ../postgresql.conf.sample /usr/share/postgresql/$POSTGRES_VERSION/  && \
    sed -ri "s!^#?(listen_addresses)\s*=\s*\S+.*!\1 = '*'!" /usr/share/postgresql/postgresql.conf.sample
RUN mkdir -p /var/run/postgresql && chown -R postgres /var/run/postgresql

ENV PATH /usr/lib/postgresql/$POSTGRES_VERSION/bin:$PATH
ENV PGDATA /var/lib/postgresql/data
VOLUME /var/lib/postgresql/data

COPY docker-entrypoint.sh /

ENTRYPOINT ["/docker-entrypoint.sh"]

EXPOSE 5432
CMD ["postgres"]