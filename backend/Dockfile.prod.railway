# -------------------------
# Stage 1: Build PHP vendor
# -------------------------
FROM composer:2 AS vendor

WORKDIR /app
COPY . /app

RUN composer install --no-dev --optimize-autoloader


# -------------------------
# Stage 2: PHP-FPM + Nginx
# -------------------------
FROM php:8.4-fpm

# Instalar dependencias del sistema
RUN apt-get update && apt-get install -y \
    unzip \
    git \
    libzip-dev \
    zip \
    nginx \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

# Extensiones PHP
RUN docker-php-ext-install pdo pdo_mysql zip

# Opcache para producción
RUN echo "opcache.enable=1\n\
opcache.memory_consumption=128\n\
opcache.max_accelerated_files=20000\n\
opcache.validate_timestamps=0" > /usr/local/etc/php/conf.d/opcache.ini

# Copiar código del backend
WORKDIR /app
COPY . /app

# Copiar vendor desde el stage 1
COPY --from=vendor /app/vendor /app/vendor

# Permisos Laravel
RUN chown -R www-data:www-data /app/storage /app/bootstrap/cache

# Copiar entrypoint
COPY docker/entrypoint.prod.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Copiar configuración de Nginx
COPY docker/nginx.conf /etc/nginx/sites-enabled/default

# Supervisor para ejecutar Nginx + PHP-FPM juntos
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Exponer puerto (Railway/Render/Fly.io usan 8080)
EXPOSE 8080

ENTRYPOINT ["entrypoint.sh"]

CMD ["/usr/bin/supervisord"]

