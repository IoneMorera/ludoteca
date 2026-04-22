#!/bin/sh
set -e

# Permisos
chown -R www-data:www-data /app/storage /app/bootstrap/cache
chmod -R 775 /app/storage /app/bootstrap/cache

# Asegurar symlink public/storage -> storage/app/public
# (necesario para servir imágenes bajo /storage/...)
rm -f /app/public/storage
php artisan storage:link --force || true

# Crear directorio para imágenes de juegos si no existe
mkdir -p /app/storage/app/public/juegos
chown -R www-data:www-data /app/storage/app/public

# Migraciones
php artisan migrate --force || true

# Caches
php artisan config:cache
php artisan route:cache
php artisan view:cache

# Multi-tenant (si lo usas)
php artisan tenants:migrate --force 2>/dev/null || true

exec "$@"
