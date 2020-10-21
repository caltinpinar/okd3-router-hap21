FROM openshift/origin-haproxy-router:v3.11

# take a look at http://www.lua.org/download.html for
# newer version

ENV HAPROXY_MAJOR=2.1 \
    HAPROXY_VERSION=2.1.8 \
    HAPROXY_SHA256=7ad288fdf55c45cb7a429b646afb0239311386a9746682787ae430b70ab1296a \
    LUA_VERSION=5.4.0 \
    LUA_URL=http://www.lua.org/ftp/lua-5.4.0.tar.gz \
    LUA_SHA256=8cdbffa8a214a23d190d7c45f38c19518ae62e89 \
    OPENSSL_VERS=1.1.1g \
    OSSP_SHA256=ddb04774f1e32f0c49751e21b67216ac87852ceb056b75209af2443400636d46

# RUN cat /etc/redhat-release
# RUN yum provides "*lib*/libc.a"

# see http://git.haproxy.org/?p=haproxy-1.6.git;a=blob_plain;f=Makefile;hb=HEAD
# for some helpful navigation of the possible "make" arguments

USER 0

COPY haproxy-config.template /var/lib/haproxy/conf/

RUN set -x \
  && yum -y erase haproxy18 \
  && yum -y update \
  && export buildDeps='pcre-devel gcc zlib-devel readline-devel perl-Module-Load-Conditional perl-Test-Harness' \
  && yum -y install pcre zlib bind-utils curl socat make ${buildDeps} \
  && mkdir -p /usr/src/openssl /usr/src/lua /usr/src/haproxy \
  && curl -sSLO https://www.openssl.org/source/openssl-${OPENSSL_VERS}.tar.gz \
  && echo "${OSSP_SHA256} openssl-${OPENSSL_VERS}.tar.gz" | sha256sum -c \
  && tar xfvz openssl-${OPENSSL_VERS}.tar.gz -C /usr/src/openssl --strip-components=1 \
  && rm openssl-${OPENSSL_VERS}.tar.gz \
  && cd /usr/src/openssl \
  && ./config --prefix=/usr/local/openssl --openssldir=/usr/local/openssl shared zlib \
  && make \
  && make install_sw install_ssldirs \
  && echo "pathmunge /usr/local/openssl/bin" > /etc/profile.d/openssl.sh \
  && echo "/usr/local/openssl/lib" > /etc/ld.so.conf.d/openssl-${OPENSSL_VERS}.conf \
  && ldconfig -v \
  && curl -SL ${LUA_URL} -o lua-${LUA_VERSION}.tar.gz \
  && echo "${LUA_SHA256} lua-${LUA_VERSION}.tar.gz" | sha1sum -c - \
  && tar -xzf lua-${LUA_VERSION}.tar.gz -C /usr/src/lua --strip-components=1 \
  && rm lua-${LUA_VERSION}.tar.gz \
  && make -C /usr/src/lua linux test install \
  && curl -SL "http://www.haproxy.org/download/${HAPROXY_MAJOR}/src/haproxy-${HAPROXY_VERSION}.tar.gz" -o haproxy.tar.gz \
  && echo "${HAPROXY_SHA256}  haproxy.tar.gz" | sha256sum -c \
  && mkdir -p /usr/src/haproxy \
  && tar -xzf haproxy.tar.gz -C /usr/src/haproxy --strip-components=1 \
  && rm haproxy.tar.gz \
  && /usr/local/openssl/bin/openssl version \
  && make -C /usr/src/haproxy \
      TARGET=linux-glibc \
      USE_PCRE=1 \
      USE_OPENSSL=1 \
      SSL_INC=/usr/local/openssl/include \
      SSL_LIB=/usr/local/openssl/lib \
      USE_ZLIB=1 \
      USE_PCRE_JIT=1 \
      USE_LUA=1 \
      EXTRA_OBJS="contrib/prometheus-exporter/service-prometheus.o" \
      all \
      install-bin \
  && mkdir -p /usr/local/etc/haproxy \
  && mkdir -p /usr/local/etc/haproxy/ssl \
  && mkdir -p /usr/local/etc/haproxy/ssl/cas \
  && mkdir -p /usr/local/etc/haproxy/ssl/crts \
  && cp -R /usr/src/haproxy/examples/errorfiles /usr/local/etc/haproxy/errors \
  && ln -s /usr/local/sbin/haproxy /usr/sbin/haproxy \
  && setcap 'cap_net_bind_service=ep' /usr/local/sbin/haproxy \
  && rm -rf /usr/src/ \
  && yum -y autoremove $buildDeps \
  && yum -y clean all \
  && chown -R :0 /var/lib/haproxy \
  && chmod -R g+w /var/lib/haproxy

USER 1001

RUN mkdir -p /var/lib/haproxy/router/{certs,cacerts,whitelists} && \
    mkdir -p /var/lib/haproxy/{conf/.tmp,run,bin,log} && \
    touch /var/lib/haproxy/conf/{{os_http_be,os_edge_reencrypt_be,os_tcp_be,os_sni_passthrough,os_route_http_redirect,cert_config,os_wildcard_domain}.map,haproxy.config}

ENV TEMPLATE_FILE=/var/lib/haproxy/conf/haproxy-config.template \
    RELOAD_SCRIPT=/var/lib/haproxy/reload-haproxy

ENTRYPOINT ["/usr/bin/openshift-router", "--v=2"]
