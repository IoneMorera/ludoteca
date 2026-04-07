FROM php:8.4-fpm

RUN apt-get update && apt-get install -y unzip git && rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-install pdo pdo_mysql

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /app

ENTRYPOINT ["entrypoint.sh"]
# Sin CMD explícito, Docker borra el CMD de la imagen base al definir ENTRYPOINT;
# entonces entrypoint hace exec "$@" sin argumentos y el contenedor sale al instante.
CMD ["php-fpm", "-F"]
