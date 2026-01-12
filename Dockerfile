FROM composer:2.9.3 AS composer

FROM debian:trixie-slim

# copy the Composer PHAR from the Composer image into the PHP image
COPY --from=composer /usr/bin/composer /usr/bin/composer

RUN apt-get update && \
    apt-get install --no-install-recommends -y php-cli php-curl php-zip unzip git patch ssh rsync curl ca-certificates && \
    apt-get clean

WORKDIR /app
