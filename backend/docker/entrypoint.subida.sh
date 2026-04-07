#!/bin/sh
set -e

composer install --no-interaction

chown -R www-data:www-data /app/storage /app/bootstrap/cache
chmod -R 775 /app/storage /app/bootstrap/cache

php artisan key:generate --force
php artisan storage:link --force 2>/dev/null || true
php artisan config:clear
php artisan route:clear
php artisan migrate --force
php artisan tenants:migrate --force 2>/dev/null || true

chown -R www-data:www-data /app/storage

exec php-fpm


