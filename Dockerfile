FROM nginx:mainline-alpine

MAINTAINER vasko <vasil.vasilev@smartmodule.ch>

ENV php_conf /etc/php5/php.ini
ENV fpm_conf /etc/php5/php-fpm.conf
ENV composer_hash aa96f26c2b67226a324c27919f1eb05f21c248b987e6195cad9690d5c1ff713d53020a02ac8c217dbf90a7eacc9d141d 
ENV PHPREDIS_VERSION 2.2.7


ENV PHPIZE_DEPS \
        autoconf \
        file \
        g++ \
        gcc \
        libc-dev \
        make \
        pkgconf \
        re2c

# Apply stack smash protection to functions using local buffers and alloca()
# Make PHP's main executable position-independent (improves ASLR security mechanism, and has no performance impact on x86_64)
# Enable optimization (-O2)
# Enable linker optimization (this sorts the hash buckets to improve cache locality, and is non-default)
# Adds GNU HASH segments to generated executables (this is used if present, and is much faster than sysv hash; in this configuration, sysv hash is also generated)
# https://github.com/docker-library/php/issues/272
ENV PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2"
ENV PHP_CPPFLAGS="$PHP_CFLAGS"
ENV PHP_LDFLAGS="-Wl,-O1 -Wl,--hash-style=both -pie"


#RUN echo @edge http://nl.alpinelinux.org/alpine/edge/main >> /etc/apk/repositories && \
RUN mkdir /usr/local/lib/php/extensions -p && \
    echo @testing http://nl.alpinelinux.org/alpine/edge/testing >> /etc/apk/repositories && \
    echo /etc/apk/respositories && \
    apk update && \
    apk add --no-cache bash \
    openssh-client \
    wget \
    supervisor \
    curl \
    git \
    autoconf \
    php5-fpm \
    php5-dev \
    file \
    g++ \
    gcc \
    libc-dev \
    make \
    pkgconf \
    re2c \
    php5-pdo \
    php5-pdo_mysql \
    php5-mysql \
    php5-mysqli \
    php5-mcrypt \
    php5-ctype \
    php5-zlib \
    php5-gd \
    php5-exif \
    php5-intl \
    php5-memcache \
    php5-sqlite3 \
    php5-pgsql \
    php5-xml \
    php5-xsl \
    php5-curl \
    php5-openssl \
    php5-iconv \
    php5-json \
    php5-phar \
    php5-soap \
    php5-dom 



RUN apk add --no-cache php5-zip \
    php5-pear \
    python \
    python-dev \
    py-pip \
    augeas-dev \
    openssl-dev \
    ca-certificates \
    dialog \
    gcc \
    musl-dev \
    linux-headers \
    libffi-dev &&\
    mkdir -p /etc/nginx && \
    mkdir -p /var/www && \
    mkdir -p /run/nginx && \
    mkdir -p /var/log/supervisor
RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" && \
    php composer-setup.php --install-dir=/usr/bin --filename=composer && \
    php -r "unlink('composer-setup.php');"
    #php -r "if (hash_file('SHA384', 'composer-setup.php') === '55d6ead61b29c7bdee5cccfb50076874187bd9f21f65d8991d46ec5cc90518f447387fb9f76ebae1fbbacf329e583e30') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;" && \

RUN pip install -U pip && \
    pip install -U certbot && \
    mkdir -p /etc/letsencrypt/webrootauth && \
    apk del gcc musl-dev linux-headers libffi-dev augeas-dev python-dev

RUN apk add --no-cache --virtual .persistent-deps \
        ca-certificates \ 
        tar \
        xz


RUN curl -L -o /tmp/redis.tar.gz https://github.com/phpredis/phpredis/archive/$PHPREDIS_VERSION.tar.gz && \
    mkdir -p /usr/src/php/ext/redis && \
    tar xfz /tmp/redis.tar.gz -C /usr/src/php/ext/redis --strip-components=1 && \
    rm -r /tmp/redis.tar.gz && \
    cd /usr/src/php/ext/redis && \
    phpize && \
    ./configure && \
    make && make install


ADD conf/supervisord.conf /etc/supervisord.conf        

#Get xdebug, compile it, install it and add it to php        
RUN mkdir -p /usr/local/lib/php/extensions/modules && \
    wget http://xdebug.org/files/xdebug-2.5.0.tgz &&  \
    tar -xvzf xdebug-2.5.0.tgz &&  \
    cd xdebug-2.5.0 &&  \
    phpize &&  \
    ./configure && \
    make &&  \
    cp modules/xdebug.so /usr/lib/php5/modules &&  \
    cp modules/xdebug.so /usr/local/lib/php/extensions/modules/xdebug.so &&  \
    echo "[xdebug]" >> /etc/php5/conf.d/xdebug.ini &&  \
    echo "zend_extension=$(find /usr/lib/php5/modules -name xdebug.so)" >> /etc/php5/conf.d/xdebug.ini && \
    rm -rf xdebug-2.5.0  \


# Copy our nginx config
RUN rm -Rf /etc/nginx/nginx.conf
ADD conf/nginx.conf /etc/nginx/nginx.conf

# nginx site conf
RUN mkdir -p /etc/nginx/sites-available/ && \
mkdir -p /etc/nginx/sites-enabled/ && \
mkdir -p /etc/nginx/ssl/ && \
rm -Rf /var/www/*

ADD conf/nginx-site.conf /etc/nginx/sites-available/default.conf
ADD conf/nginx-site-ssl.conf /etc/nginx/sites-available/default-ssl.conf

RUN ln -s /etc/nginx/sites-available/default.conf /etc/nginx/sites-enabled/default.conf

# tweak php-fpm config
RUN sed -i \
        -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" \
        -e "s/upload_max_filesize\s*=\s*2M/upload_max_filesize = 100M/g" \
        -e "s/post_max_size\s*=\s*8M/post_max_size = 100M/g" \
        -e "s/variables_order = \"GPCS\"/variables_order = \"EGPCS\"/g" \
        ${php_conf} && \
    sed -i \
        -e "s/;daemonize\s*=\s*yes/daemonize = no/g" \
        -e "s/;catch_workers_output\s*=\s*yes/catch_workers_output = yes/g" \
        -e "s/pm.max_children = 4/pm.max_children = 4/g" \
        -e "s/pm.start_servers = 2/pm.start_servers = 3/g" \
        -e "s/pm.min_spare_servers = 1/pm.min_spare_servers = 2/g" \
        -e "s/pm.max_spare_servers = 3/pm.max_spare_servers = 4/g" \
        -e "s/pm.max_requests = 500/pm.max_requests = 200/g" \
        -e "s/user = nobody/user = nginx/g" \
        -e "s/group = nobody/group = nginx/g" \
        -e "s/;listen.mode = 0660/listen.mode = 0666/g" \
        -e "s/;listen.owner = nobody/listen.owner = nginx/g" \
        -e "s/;listen.group = nobody/listen.group = nginx/g" \
        -e "s/listen = 127.0.0.1:9000/listen = \/var\/run\/php-fpm.sock/g" \
        -e "s/^;clear_env = no$/clear_env = no/" \
        ${fpm_conf} && \
    ln -s /etc/php5/php.ini /etc/php5/conf.d/php.ini && \
    find /etc/php5/conf.d/ -name "*.ini" -exec sed -i -re 's/^(\s*)#(.*)/\1;\2/g' {} \;

# Add Scripts
ADD scripts/start.sh /start.sh
ADD scripts/pull /usr/bin/pull
ADD scripts/push /usr/bin/push
ADD scripts/letsencrypt-setup /usr/bin/letsencrypt-setup
ADD scripts/letsencrypt-renew /usr/bin/letsencrypt-renew
RUN chmod 755 /usr/bin/pull \
    && chmod 755 /usr/bin/push \
    && chmod 755 /usr/bin/letsencrypt-setup \
    && chmod 755 /usr/bin/letsencrypt-renew \
    && chmod 755 /start.sh

# copy in code
#ADD src/ /var/www/html/
#ADD errors/ /var/www/errors/

VOLUME /var/www

EXPOSE 443 80

#CMD ["/usr/bin/supervisord", "-n", "-c",  "/etc/supervisord.conf"]
CMD ["/start.sh"]
