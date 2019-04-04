FROM php:7.1-fpm

WORKDIR /var/www

# Install Laravel and Composer's required PHP Extensions

RUN apt-get update && apt-get install -y openssl curl zlib1g-dev
RUN docker-php-ext-install mbstring pdo_mysql zip

RUN apt-get update -y && apt-get install -y sendmail libpng-dev

RUN apt-get update && \
    apt-get install -y \
        zlib1g-dev

RUN docker-php-ext-install gd

# Configure XDebug

RUN yes | pecl install xdebug \
    && echo "zend_extension=$(find /usr/local/lib/php/extensions/ -name xdebug.so)" > /usr/local/etc/php/conf.d/xdebug.ini \
    && echo "xdebug.remote_enable=on" >> /usr/local/etc/php/conf.d/xdebug.ini \
    && echo "xdebug.remote_autostart=on" >> /usr/local/etc/php/conf.d/xdebug.ini

# Install Composer 

ENV COMPOSER_ALLOW_SUPERUSER 1

RUN curl --silent --show-error https://getcomposer.org/installer | php

RUN mv composer.phar /usr/local/bin/composer

# Move app code into container

COPY . .

RUN composer install

# In my own (marco here) setup, I ran into an issue the app environment ran out of workers to handle my requests (the default is 5). The below fixes it for me.
RUN echo "pm = dynamic" >> /usr/local/etc/php-fpm.conf
RUN echo "pm.max_children = 1000" >> /usr/local/etc/php-fpm.conf