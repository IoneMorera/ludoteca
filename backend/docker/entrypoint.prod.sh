#!/bin/sh
set -e

echo "=== Ludoteca Backend - Produccion ==="

echo "[1/7] Instalando dependencias..."
composer install --no-interaction --no-dev --optimize-autoloader

echo "[2/7] Configurando permisos..."
chown -R www-data:www-data /app/storage /app/bootstrap/cache
chmod -R 775 /app/storage /app/bootstrap/cache

if [ -z "$APP_KEY" ] || [ "$APP_KEY" = "" ]; then
    echo "[3/7] Generando APP_KEY..."
    php artisan key:generate --force
else
    echo "[3/7] APP_KEY ya configurada, saltando..."
fi

echo "[4/7] Creando enlace de storage..."
php artisan storage:link --force 2>/dev/null || true

echo "[5/7] Optimizando cache..."
php artisan config:cache
php artisan route:cache
php artisan view:cache

echo "[6/7] Ejecutando migraciones..."
php artisan migrate --force
php artisan tenants:migrate --force 2>/dev/null || true

echo "[7/7] Configurando permisos finales..."
chown -R www-data:www-data /app/storage

echo "=== Backend listo. Iniciando PHP-FPM ==="
exec php-fpm
