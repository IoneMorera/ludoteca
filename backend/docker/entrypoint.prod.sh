#!/bin/sh
set -e

# Permisos
chown -R www-data:www-data /app/storage /app/bootstrap/cache
chmod -R 775 /app/storage /app/bootstrap/cache

# Migraciones
php artisan migrate --force || true

# Caches
php artisan config:cache
php artisan route:cache
php artisan view:cache

# Multi-tenant (si lo usas)
php artisan tenants:migrate --force 2>/dev/null || true

exec "$@"
