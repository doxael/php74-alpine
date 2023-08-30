#PHP docker By Doxael Avila
FROM php:7.4.29-fpm-alpine3.16

LABEL maintainer="Doxael Avila <doxael@gmail.com>"

ARG VERSION_OS
ENV VERSION_OS=${VERSION_OS}

### ----------------------------------------------------------
# Proper iconv #240
#   Ref: https://github.com/docker-library/php/issues/240
### ----------------------------------------------------------

ENV LD_PRELOAD /usr/lib/preloadable_libiconv.so php
RUN apk add --no-cache --repository http://dl-3.alpinelinux.org/alpine/edge/community gnu-libiconv

### ----------------------------------------------------------
### Part 1 of Nginx Dockerfile source https://hub.docker.com/_/nginx/
### https://github.com/nginxinc/docker-nginx/blob/b18fb328f999b28a7bb6d86e06b0756c1befa21a/stable/alpine/Dockerfile
### ----------------------------------------------------------
# FROM alpine:3.16
# LABEL maintainer="NGINX Docker Maintainers <docker-maint@nginx.com>"

ENV NGINX_VERSION 1.22.0
ENV NJS_VERSION   0.7.4
ENV PKG_RELEASE   1

RUN set -x \
    # create nginx user/group first, to be consistent throughout docker variants
    && addgroup -g 1000 -S nginx \
    && adduser -S -D -H -u 1000 -h /var/cache/nginx -s /sbin/nologin -G nginx -g nginx nginx \
    && apkArch="$(cat /etc/apk/arch)" \
    && nginxPackages=" \
    nginx=${NGINX_VERSION}-r${PKG_RELEASE} \
    nginx-module-xslt=${NGINX_VERSION}-r${PKG_RELEASE} \
    nginx-module-geoip=${NGINX_VERSION}-r${PKG_RELEASE} \
    nginx-module-image-filter=${NGINX_VERSION}-r${PKG_RELEASE} \
    nginx-module-njs=${NGINX_VERSION}.${NJS_VERSION}-r${PKG_RELEASE} \
    " \
    # install prerequisites for public key and pkg-oss checks
    && apk add --no-cache --virtual .checksum-deps \
    openssl \
    && case "$apkArch" in \
    x86_64|aarch64) \
    # arches officially built by upstream
    set -x \
    && KEY_SHA512="e7fa8303923d9b95db37a77ad46c68fd4755ff935d0a534d26eba83de193c76166c68bfe7f65471bf8881004ef4aa6df3e34689c305662750c0172fca5d8552a *stdin" \
    && wget -O /tmp/nginx_signing.rsa.pub https://nginx.org/keys/nginx_signing.rsa.pub \
    && if [ "$(openssl rsa -pubin -in /tmp/nginx_signing.rsa.pub -text -noout | openssl sha512 -r)" = "$KEY_SHA512" ]; then \
    echo "key verification succeeded!"; \
    mv /tmp/nginx_signing.rsa.pub /etc/apk/keys/; \
    else \
    echo "key verification failed!"; \
    exit 1; \
    fi \
    && apk add -X "https://nginx.org/packages/alpine/v$(egrep -o '^[0-9]+\.[0-9]+' /etc/alpine-release)/main" --no-cache $nginxPackages \
    ;; \
    *) \
    # we're on an architecture upstream doesn't officially build for
    # let's build binaries from the published packaging sources
    set -x \
    && tempDir="$(mktemp -d)" \
    && chown nobody:nobody $tempDir \
    && apk add --no-cache --virtual .build-deps \
    gcc \
    libc-dev \
    make \
    openssl-dev \
    pcre2-dev \
    zlib-dev \
    linux-headers \
    libxslt-dev \
    gd-dev \
    geoip-dev \
    perl-dev \
    libedit-dev \
    bash \
    alpine-sdk \
    findutils \
    && su nobody -s /bin/sh -c " \
    export HOME=${tempDir} \
    && cd ${tempDir} \
    && curl -f -O https://hg.nginx.org/pkg-oss/archive/696.tar.gz \
    && PKGOSSCHECKSUM=\"fabf394af60d935d7c3f5e36db65dddcced9595fd06d3dfdfabbb77aaea88a5b772ef9c1521531673bdbb2876390cdea3b81c51030d36ab76cf5bfc0bfe79230 *696.tar.gz\" \
    && if [ \"\$(openssl sha512 -r 696.tar.gz)\" = \"\$PKGOSSCHECKSUM\" ]; then \
    echo \"pkg-oss tarball checksum verification succeeded!\"; \
    else \
    echo \"pkg-oss tarball checksum verification failed!\"; \
    exit 1; \
    fi \
    && tar xzvf 696.tar.gz \
    && cd pkg-oss-696 \
    && cd alpine \
    && make all \
    && apk index -o ${tempDir}/packages/alpine/${apkArch}/APKINDEX.tar.gz ${tempDir}/packages/alpine/${apkArch}/*.apk \
    && abuild-sign -k ${tempDir}/.abuild/abuild-key.rsa ${tempDir}/packages/alpine/${apkArch}/APKINDEX.tar.gz \
    " \
    && cp ${tempDir}/.abuild/abuild-key.rsa.pub /etc/apk/keys/ \
    && apk del .build-deps \
    && apk add -X ${tempDir}/packages/alpine/ --no-cache $nginxPackages \
    ;; \
    esac \
    # remove checksum deps
    && apk del .checksum-deps \
    # if we have leftovers from building, let's purge them (including extra, unnecessary build deps)
    && if [ -n "$tempDir" ]; then rm -rf "$tempDir"; fi \
    && if [ -n "/etc/apk/keys/abuild-key.rsa.pub" ]; then rm -f /etc/apk/keys/abuild-key.rsa.pub; fi \
    && if [ -n "/etc/apk/keys/nginx_signing.rsa.pub" ]; then rm -f /etc/apk/keys/nginx_signing.rsa.pub; fi \
    # Bring in gettext so we can get `envsubst`, then throw
    # the rest away. To do this, we need to install `gettext`
    # then move `envsubst` out of the way so `gettext` can
    # be deleted completely, then move `envsubst` back.
    && apk add --no-cache --virtual .gettext gettext \
    && mv /usr/bin/envsubst /tmp/ \
    \
    && runDeps="$( \
    scanelf --needed --nobanner /tmp/envsubst \
    | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
    | sort -u \
    | xargs -r apk info --installed \
    | sort -u \
    )" \
    && apk add --no-cache $runDeps \
    && apk del .gettext \
    && mv /tmp/envsubst /usr/local/bin/ \
    # Bring in tzdata so users could set the timezones through the environment
    # variables
    && apk add --no-cache tzdata \
    # Bring in curl and ca-certificates to make registering on DNS SD easier
    && apk add --no-cache curl ca-certificates \
    # forward request and error logs to docker log collector
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log \
    # create a docker-entrypoint.d directory
    && mkdir /docker-entrypoint.d  

# 2 Step, added common-SO extensions for PHP
RUN apk update && apk add --no-cache \
    curl \
    libpng-dev \
    libxml2-dev \
    zip \
    unzip \
    libzip-dev \ 
    oniguruma-dev \
    oniguruma \
    zlib \
    zlib-dev \
    libpq-dev \
    bash    \
    nano 

# We add here the php extensions to have the php whole environment (in this case for specific requirement)
    RUN docker-php-ext-install pdo pdo_mysql 
    RUN docker-php-ext-install mbstring 
    RUN docker-php-ext-install bcmath 
    RUN docker-php-ext-install ctype 
    RUN docker-php-ext-install fileinfo 
    RUN docker-php-ext-install mysqli 
    RUN docker-php-ext-enable mysqli 
    RUN docker-php-ext-install gd 
    RUN docker-php-ext-install zip 

EXPOSE 80

STOPSIGNAL SIGTERM

### ----------------------------------------------------------
### Setup supervisord, nginx config
### ----------------------------------------------------------

RUN set -x && \
    apk update && apk upgrade && \
    apk add --no-cache \
    supervisor \
    && \
    rm -Rf /etc/nginx/nginx.conf && \
    rm -Rf /etc/nginx/conf.d/default.conf && \
    # folders
    mkdir -p /var/log/supervisor

#We add here the config internal files (edited by separated)
COPY conf/supervisord.conf /etc/supervisord.conf
COPY conf/nginx.conf /etc/nginx/nginx.conf
COPY conf/nginx-default.conf /etc/nginx/conf.d/default.conf

CMD ["/docker-entrypoint.sh"]