FROM wordpress:php8.1 AS wpbuild

# Updates from https://github.com/RobDWaller/dusty/blob/master/docker/Dockerfile
# add PHP Composer to the stack
RUN apt-get update \
    && apt-get install -y git zip unzip libcap2-bin openssl \
    && rm -rf /var/lib/apt/lists/*

# Add workspace domain name to /etc/hosts
#RUN if [[ -z cat /etc/hosts | grep "${PROJECT_DOMAIN}" ]]; then sed -i '/^127.0.0.1* 127.0.0.1\t${PROJECT_DOMAIN}' /etc/hosts; fi

#
# Install PHP Composer to /usr/bin/composer
# Note that the hash needs to be updated when Composer is updated
#
WORKDIR /root
ENV COMPOSER=dac665fdc30fdd8ec78b38b9800061b4150413ff2e3b6f88543c636f7cd84f6db9189d43a81e5503cda447da73c7e5b6
    #&& php -r "if (hash_file('SHA384', 'composer-setup.php') === '$COMPOSER') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;" \
RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" \
    && php -r "copy('https://getcomposer.org/installer','composer-setup.php');" \
    && php -r "if (hash_file('SHA384','composer-setup.php') === trim(file_get_contents('https://composer.github.io/installer.sig'))) { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;" \
    && php composer-setup.php --install-dir=/usr/local/bin \
    && php -r "unlink('composer-setup.php');" \
    && cp -r /usr/local/bin/composer.phar /usr/local/bin/composer \
    && export PATH="${PATH}:/usr/local/bin" >> ~/.bashrc

# this is necessary so that we can run container as www-data, not as root
#RUN setcap 'cap_net_bind_service=+ep' /usr/sbin/apache2
#RUN getcap /usr/sbin/apache2

# Extend PHP Resource limits
COPY config/ptek-resources.ini /usr/local/etc/php/conf.d/

#COPY --from=build /etc/apache2 config/apache/wp


FROM wpbuild AS wpconfigure
WORKDIR /etc
COPY --from=wpbuild /etc/apache2 config/apache/wp

# copy all of our development code
WORKDIR /var/www/html
