# Despliegue en produccion - Ludoteca

## Requisitos previos

- **Servidor VPS** con Ubuntu 22.04+ (recomendado: Oracle Cloud Free Tier - ARM Ampere A1, 4 CPU, 24 GB RAM gratuito)
- **Dominio** apuntando a la IP publica del servidor (registro A en tu proveedor DNS)
- **Puertos abiertos**: 80 (HTTP), 443 (HTTPS), 22 (SSH)

## 1. Preparar el servidor

Conectate al servidor por SSH y ejecuta:

```bash
# Actualizar sistema
sudo apt update && sudo apt upgrade -y

# Instalar Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Instalar Docker Compose plugin
sudo apt install -y docker-compose-plugin

# Cerrar sesion y reconectar para que aplique el grupo docker
exit
```

Reconecta por SSH y verifica:

```bash
docker --version
docker compose version
```

## 2. Subir el proyecto al servidor

Desde tu maquina local:

```bash
# Opcion A: Git (recomendado)
# En el servidor:
git clone <URL_DE_TU_REPOSITORIO> ~/ludoteca
cd ~/ludoteca

# Opcion B: rsync (si no usas Git)
rsync -avz --exclude node_modules --exclude vendor --exclude .git \
  . usuario@IP_SERVIDOR:~/ludoteca/
```

## 3. Configurar variables de entorno

En el servidor, edita el archivo `.env.production`:

```bash
cd ~/ludoteca
cp .env.production .env.production.bak  # Solo si ya existia
nano .env.production
```

Cambia **todos** los valores `TU_DOMINIO` por tu dominio real y `CAMBIA_ESTA_PASSWORD` por una contrasena segura para MySQL.

Ejemplo con dominio `ludoteca.ejemplo.com`:

```
DOMAIN=ludoteca.ejemplo.com
APP_URL=https://ludoteca.ejemplo.com
SESSION_DOMAIN=.ludoteca.ejemplo.com
SANCTUM_STATEFUL_DOMAINS=ludoteca.ejemplo.com
CORS_ALLOWED_ORIGINS=https://ludoteca.ejemplo.com
VITE_API_URL=https://ludoteca.ejemplo.com/api
VITE_BACKEND_URL=https://ludoteca.ejemplo.com
DB_PASSWORD=mi_password_seguro_123
```

Genera la APP_KEY:

```bash
# Arrancar temporalmente para generar la key
docker compose -f docker-compose.prod.yml run --rm backend php artisan key:generate --show
```

Copia la key generada (empieza con `base64:...`) y ponla en `.env.production`:

```
APP_KEY=base64:XXXXXXXXXXXXXXXXXXXXXXXXXX
```

## 4. Abrir puertos en Oracle Cloud

En la consola de Oracle Cloud:

1. Ve a **Networking > Virtual Cloud Networks > tu VCN > Security Lists**
2. Anade reglas de entrada (Ingress Rules):
   - **Puerto 80**: Source `0.0.0.0/0`, TCP, Destination Port `80`
   - **Puerto 443**: Source `0.0.0.0/0`, TCP, Destination Port `443`

Tambien en el firewall del servidor:

```bash
sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 443 -j ACCEPT
sudo netfilter-persistent save
```

## 5. Construir y arrancar

```bash
cd ~/ludoteca

# Construir imagenes (primera vez tarda unos minutos)
docker compose -f docker-compose.prod.yml build

# Arrancar en segundo plano
docker compose -f docker-compose.prod.yml up -d
```

Caddy obtendra automaticamente un certificado SSL de Let's Encrypt.

## 6. Verificar

```bash
# Ver logs de todos los servicios
docker compose -f docker-compose.prod.yml logs -f

# Ver solo logs del backend
docker compose -f docker-compose.prod.yml logs -f backend

# Ver solo logs de Caddy
docker compose -f docker-compose.prod.yml logs -f caddy

# Verificar que todos los contenedores estan corriendo
docker compose -f docker-compose.prod.yml ps
```

Abre `https://tu-dominio.com` en el navegador. Deberia aparecer la pagina de login.

## Comandos utiles

```bash
# Parar todos los servicios
docker compose -f docker-compose.prod.yml down

# Reiniciar un servicio especifico
docker compose -f docker-compose.prod.yml restart backend

# Reconstruir despues de cambios en el codigo
docker compose -f docker-compose.prod.yml build && docker compose -f docker-compose.prod.yml up -d

# Ejecutar migraciones manualmente
docker compose -f docker-compose.prod.yml exec backend php artisan migrate --force

# Ejecutar migraciones de tenants
docker compose -f docker-compose.prod.yml exec backend php artisan tenants:migrate --force

# Ver bases de datos de tenants
docker compose -f docker-compose.prod.yml exec mysql mysql -uroot -p -e "SHOW DATABASES;"

# Backup de la base de datos
docker compose -f docker-compose.prod.yml exec mysql mysqldump -uroot -p --all-databases > backup_$(date +%Y%m%d).sql
```

## Actualizar el proyecto

Cuando hagas cambios en el codigo:

```bash
cd ~/ludoteca
git pull origin main   # o la rama que uses

# Reconstruir y reiniciar
docker compose -f docker-compose.prod.yml build
docker compose -f docker-compose.prod.yml up -d
```

## Solucion de problemas

**Caddy no obtiene certificado SSL**: Verifica que el dominio apunta a la IP del servidor (`ping tu-dominio.com`) y que los puertos 80/443 estan abiertos.

**Error 502 Bad Gateway**: El backend aun no esta listo. Espera unos segundos y revisa `docker compose -f docker-compose.prod.yml logs backend`.

**Error de conexion a MySQL**: Verifica que `DB_HOST=mysql` en `.env.production` (nombre del servicio Docker, no localhost).

**Las imagenes de juegos no se ven**: Ejecuta `docker compose -f docker-compose.prod.yml exec backend php artisan storage:link --force`.
