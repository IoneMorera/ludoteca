#!/bin/sh
set -e

# Dependencias PHP (el volumen named backend-vendor puede estar vacío la primera vez)
if [ ! -f /app/vendor/autoload.php ]; then
  echo "entrypoint: instalando dependencias con Composer..."
  composer install --no-interaction --prefer-dist --no-progress
fi

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