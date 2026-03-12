# Guia de Despliegue - Ludoteca en Oracle Cloud

## Requisitos previos

- Cuenta en Oracle Cloud con Free Tier activo
- Instancia VM creada: **VM.Standard.A1.Flex** (2 OCPUs, 12 GB RAM, Ubuntu 22.04 aarch64)
- IP publica asignada a la instancia
- Clave SSH privada descargada en tu PC (fichero .pem o .key)

---

## PASO 1: Abrir puertos en Oracle Cloud

### 1.1 - Security Lists (consola web de Oracle)

1. Ve a **Networking > Virtual Cloud Networks**
2. Haz clic en tu VCN (`ludoteca-vcn`)
3. Haz clic en la **subnet publica**
4. Haz clic en la **Security List** asociada (normalmente `Default Security List for ludoteca-vcn`)
5. Pulsa **Add Ingress Rules** y anade estas reglas:

| Source CIDR   | Protocol | Dest Port | Descripcion |
|---------------|----------|-----------|-------------|
| 0.0.0.0/0     | TCP      | 80        | HTTP        |
| 0.0.0.0/0     | TCP      | 443       | HTTPS       |

> El puerto 22 (SSH) ya deberia estar abierto por defecto.

### 1.2 - Firewall del sistema operativo (dentro de la VM)

Oracle Linux/Ubuntu tienen un firewall interno que tambien bloquea puertos.
Esto se hace DESPUES de conectarse por SSH (Paso 2).

---

## PASO 2: Conectarse a la VM por SSH

### Desde Windows (PowerShell)

```powershell
ssh -i "C:\ruta\a\tu\clave-privada.key" ubuntu@TU_IP_PUBLICA
```

> Si te da error de permisos en la clave, ejecuta primero:
> ```powershell
> icacls "C:\ruta\a\tu\clave-privada.key" /inheritance:r /grant:r "%USERNAME%:R"
> ```
> Esto restringe los permisos del fichero para que solo tu usuario pueda leerlo.

### Primera vez conectado - Verificar

Una vez dentro, deberia aparecer algo como:
```
Welcome to Ubuntu 22.04.x LTS (GNU/Linux ...)
ubuntu@ludoteca-instance:~$
```

---

## PASO 3: Abrir firewall del SO

Ejecuta estos comandos dentro de la VM:

```bash
sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 443 -j ACCEPT
sudo apt-get install -y iptables-persistent
sudo netfilter-persistent save
```

> Cuando pregunte si quieres guardar las reglas IPv4, responde **Yes**.
> Cuando pregunte si quieres guardar las reglas IPv6, responde **Yes**.

---

## PASO 4: Instalar Docker

```bash
# Actualizar el sistema
sudo apt-get update && sudo apt-get upgrade -y

# Instalar Docker
curl -fsSL https://get.docker.com | sh

# Anadir tu usuario al grupo docker (para no necesitar sudo)
sudo usermod -aG docker $USER

# IMPORTANTE: Cerrar sesion y volver a conectar para que se aplique
exit
```

Vuelve a conectarte:
```powershell
ssh -i "C:\ruta\a\tu\clave-privada.key" ubuntu@TU_IP_PUBLICA
```

Verifica que Docker funciona:
```bash
docker --version
docker compose version
```

Deberia mostrar algo como:
```
Docker version 27.x.x
Docker Compose version v2.x.x
```

---

## PASO 5: Instalar Git y clonar el proyecto

```bash
sudo apt-get install -y git
```

### Opcion A: Clonar desde repositorio Git (recomendado)

Si tienes el proyecto en GitHub/GitLab:
```bash
git clone https://github.com/TU_USUARIO/ludoteca.git
cd ludoteca
```

### Opcion B: Subir por SCP desde tu PC

Si NO tienes repositorio remoto, desde tu PC (PowerShell):
```powershell
scp -i "C:\ruta\a\tu\clave-privada.key" -r "C:\Users\desar\OneDrive\Documentos\Proyectos\ludoteca" ubuntu@TU_IP_PUBLICA:~/ludoteca
```

> Esto tardara varios minutos dependiendo de tu conexion.
> NOTA: Excluye la carpeta `node_modules` y `vendor` antes de subir para que sea mas rapido.
> Puedes crear un zip primero:
> ```powershell
> # Desde tu PC, en la carpeta del proyecto
> tar -czf ludoteca.tar.gz --exclude=node_modules --exclude=vendor --exclude=.git --exclude="mobile/build" ludoteca
> scp -i "C:\ruta\a\tu\clave-privada.key" ludoteca.tar.gz ubuntu@TU_IP_PUBLICA:~/
> ```
> Y en la VM:
> ```bash
> tar -xzf ludoteca.tar.gz
> cd ludoteca
> ```

---

## PASO 6: Configurar variables de entorno

### 6.1 - Backend (.env)

```bash
cd ~/ludoteca
cp backend/.env.production backend/.env
```

Ahora edita el fichero para poner TU IP PUBLICA:
```bash
nano backend/.env
```

Busca y reemplaza **TODAS** las apariciones de `TU_IP_PUBLICA` por tu IP real.
Las lineas que debes cambiar son:

```
APP_URL=http://123.456.789.10
SESSION_DOMAIN=123.456.789.10
SANCTUM_STATEFUL_DOMAINS=123.456.789.10
CORS_ALLOWED_ORIGINS=http://123.456.789.10
```

> Sustituye `123.456.789.10` por tu IP publica real.

Para guardar en nano: `Ctrl+O`, Enter, `Ctrl+X`.

### 6.2 - Docker Compose (.env)

```bash
cp .env.prod .env
nano .env
```

Reemplaza `TU_IP_PUBLICA` por tu IP real:
```
DB_PASSWORD=LudotecaSecure2026!
VITE_API_URL=http://123.456.789.10/api
VITE_BACKEND_URL=http://123.456.789.10
```

Guarda y cierra (`Ctrl+O`, Enter, `Ctrl+X`).

---

## PASO 7: Desplegar

```bash
cd ~/ludoteca
docker compose -f docker-compose.prod.yml up -d --build
```

> La primera ejecucion tardara **5-10 minutos** porque:
> - Descarga las imagenes Docker (MySQL, PHP, Node, Nginx)
> - Compila el frontend (npm ci + npm run build)
> - Instala dependencias PHP (composer install)
> - Ejecuta migraciones de base de datos

### Seguir el progreso en tiempo real

```bash
docker compose -f docker-compose.prod.yml logs -f
```

> Pulsa `Ctrl+C` para dejar de ver los logs.

### Verificar que todos los contenedores estan corriendo

```bash
docker compose -f docker-compose.prod.yml ps
```

Deberia mostrar 4 contenedores:
```
NAME                    STATUS
ludoteca-mysql          running (healthy)
ludoteca-backend        running
ludoteca-frontend       exited (0)      <-- normal, solo compila y sale
ludoteca-nginx          running
```

> El contenedor `frontend` aparece como "exited" porque su unico trabajo es
> compilar Vue.js y copiar los ficheros. Una vez hecho, se detiene. Es normal.

---

## PASO 8: Verificar el despliegue

### Desde el navegador

1. Abre `http://TU_IP_PUBLICA` - Deberia aparecer la web de Ludoteca (frontend Vue.js)
2. Prueba a hacer login con tus credenciales

### Desde la app movil

1. Abre la app Ludoteca
2. Toca **"Configurar servidor"** debajo del boton de login
3. Escribe: `http://TU_IP_PUBLICA`
4. Haz login normalmente

---

## Comandos utiles de mantenimiento

### Ver logs de un servicio especifico
```bash
cd ~/ludoteca
docker compose -f docker-compose.prod.yml logs backend    # logs del backend PHP
docker compose -f docker-compose.prod.yml logs nginx       # logs de Nginx
docker compose -f docker-compose.prod.yml logs mysql       # logs de MySQL
```

### Reiniciar todos los servicios
```bash
docker compose -f docker-compose.prod.yml restart
```

### Parar todo
```bash
docker compose -f docker-compose.prod.yml down
```

### Actualizar el proyecto (despues de hacer cambios)
```bash
cd ~/ludoteca
git pull                                                    # si usas Git
docker compose -f docker-compose.prod.yml up -d --build     # reconstruir
```

### Acceder a la base de datos
```bash
docker exec -it ludoteca-mysql mysql -u root -pLudotecaSecure2026! ludoteca
```

### Ejecutar comandos artisan
```bash
docker exec -it ludoteca-backend php artisan migrate --force
docker exec -it ludoteca-backend php artisan tenants:migrate --force
```

---

## Solucion de problemas

### La web no carga (Connection refused)
1. Verifica que los contenedores estan corriendo: `docker compose -f docker-compose.prod.yml ps`
2. Verifica los puertos de Oracle Cloud (Security List)
3. Verifica el firewall: `sudo iptables -L INPUT -n | grep 80`

### Error 502 Bad Gateway
El backend PHP no esta listo aun. Espera 1-2 minutos y recarga.
Si persiste, revisa los logs: `docker compose -f docker-compose.prod.yml logs backend`

### Error 500 Internal Server Error
```bash
docker exec -it ludoteca-backend cat /app/storage/logs/laravel.log | tail -50
```

### La app movil no conecta
1. Verifica que la URL es correcta (con `http://`, sin barra final)
2. Verifica que puedes acceder desde el navegador del movil a `http://TU_IP_PUBLICA`
3. El movil debe tener conexion a internet (no funciona solo con red local)

---

## Anadir dominio y SSL (opcional, para mas adelante)

### 1. Conseguir un dominio

Opciones baratas:
- **Porkbun**: desde ~8 EUR/ano para .com
- **Namecheap**: desde ~9 EUR/ano
- **Cloudflare Registrar**: precio de coste (~9 EUR/ano)

Opciones gratuitas (subdominio):
- **DuckDNS** (duckdns.org): subdominio gratuito tipo `tuapp.duckdns.org`
- **No-IP** (noip.com): subdominio gratuito tipo `tuapp.ddns.net`

### 2. Configurar DNS

En el panel de tu proveedor de dominio, crea un registro:
- **Tipo**: A
- **Nombre**: @ (o el subdominio que quieras)
- **Valor**: TU_IP_PUBLICA
- **TTL**: 300

### 3. Instalar SSL con Certbot

Dentro de la VM:
```bash
sudo apt-get install -y certbot
sudo certbot certonly --standalone -d tudominio.com --agree-tos -m tu@email.com
```

> Nota: Para que funcione, debes parar Nginx temporalmente:
> ```bash
> docker compose -f docker-compose.prod.yml stop nginx
> sudo certbot certonly --standalone -d tudominio.com
> docker compose -f docker-compose.prod.yml start nginx
> ```

### 4. Actualizar Nginx para HTTPS

Edita `backend/docker/nginx.prod.conf` para anadir el bloque HTTPS (443) y redireccion HTTP->HTTPS.
Monta los certificados como volumenes en el contenedor Nginx del docker-compose.

### 5. Actualizar variables

En `backend/.env`:
```
APP_URL=https://tudominio.com
SESSION_DOMAIN=tudominio.com
SANCTUM_STATEFUL_DOMAINS=tudominio.com
CORS_ALLOWED_ORIGINS=https://tudominio.com
```

En `.env` (raiz):
```
VITE_API_URL=https://tudominio.com/api
VITE_BACKEND_URL=https://tudominio.com
```

Reconstruir:
```bash
docker compose -f docker-compose.prod.yml up -d --build
```

### 6. App movil

En la app, cambia la URL del servidor a `https://tudominio.com` (desde login o menu Mas).
No necesitas recompilar el APK.
