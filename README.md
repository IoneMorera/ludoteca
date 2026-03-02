# Ludoteca - Sistema de Gestión

Sistema completo para la gestión de una ludoteca: juegos, socios, categorías y préstamos.

## Estructura del Proyecto

```
ludoteca/
├── backend/          # API REST con Laravel 11
│   ├── app/
│   │   ├── Http/Controllers/Api/   # Controladores API
│   │   ├── Models/                  # Modelos Eloquent
│   │   └── Providers/               # Service Providers
│   ├── config/                      # Configuración
│   ├── database/
│   │   ├── migrations/              # Migraciones de BD
│   │   └── seeders/                 # Datos de ejemplo
│   ├── routes/                      # Rutas API y web
│   ├── composer.json
│   └── .env.example
│
├── frontend/         # SPA con Vue 3 + Vite
│   ├── src/
│   │   ├── api/           # Cliente Axios
│   │   ├── components/    # Componentes reutilizables
│   │   ├── router/        # Vue Router
│   │   ├── stores/        # Pinia stores
│   │   ├── views/         # Vistas/páginas
│   │   ├── App.vue
│   │   ├── main.js
│   │   └── style.css      # Estilos globales
│   ├── package.json
│   └── .env.example
│
└── README.md
```

## Entidades del Sistema

| Entidad      | Descripción                                    |
|-------------|------------------------------------------------|
| Categorías  | Clasificación de juegos (mesa, cartas, etc.)   |
| Juegos      | Catálogo de juegos de la ludoteca              |
| Préstamos   | Control de préstamos y devoluciones de juegos  |

## Requisitos Previos

### Opción A: Con Docker (recomendado)

- **Docker** y **Docker Compose**
- **Node.js** >= 18
- **npm** >= 9

### Opción B: Instalación local

- **PHP** >= 8.2
- **Composer**
- **Node.js** >= 18
- **npm** >= 9
- **MySQL** o **MariaDB**

## Instalación con Docker

Docker levanta automáticamente el backend (PHP 8.4 + Composer) y MySQL 8.0. Solo el frontend se ejecuta de forma local con Node.js.

### 1. Backend + Base de datos

```bash
docker compose up -d
```

Esto realiza de forma automática:
- Arranca un contenedor MySQL 8.0 con la base de datos `ludoteca`
- Construye una imagen PHP 8.4 con las extensiones necesarias (`pdo_mysql`)
- Instala las dependencias de Composer
- Genera la APP_KEY
- Ejecuta las migraciones
- Carga los datos de ejemplo (seeders)
- Inicia `php artisan serve` en el puerto 8000

El backend estará disponible en `http://localhost:8000`

### 2. Frontend

```bash
cd frontend
npm install
npm run dev
```

El frontend estará disponible en `http://localhost:5173`

### Comandos útiles de Docker

```bash
# Ver logs del backend en tiempo real
docker compose logs -f backend

# Detener todos los servicios
docker compose down

# Detener y eliminar los datos de la base de datos
docker compose down -v

# Reiniciar solo el backend
docker compose restart backend

# Ejecutar un comando artisan dentro del contenedor
docker compose exec backend php artisan migrate:fresh --seed
```

## Conexión a la Base de Datos

La base de datos MySQL corre dentro de Docker y expone el puerto **3306** en `localhost`. Usa estos datos para conectar desde cualquier gestor (DBeaver, HeidiSQL, MySQL Workbench) o extensión de VS Code (Database Client, MySQL de Weijan Chen, etc.):

| Parámetro       | Valor         |
|-----------------|---------------|
| **Host**        | `localhost`   |
| **Puerto**      | `3306`        |
| **Usuario**     | `root`        |
| **Contraseña**  | `root`        |
| **Base de datos**| `ludoteca`   |

### Desde la terminal (cliente MySQL del contenedor)

```bash
docker compose exec mysql mysql -uroot -proot ludoteca
```

Una vez dentro puedes ejecutar consultas SQL directamente:

```sql
SHOW TABLES;
SELECT * FROM juegos;
SELECT * FROM categorias;
```

## Instalación local (sin Docker)

### Backend (Laravel)

```bash
cd backend

# Instalar dependencias PHP
composer install

# Configurar entorno
cp .env.example .env
php artisan key:generate

# Configurar la base de datos en .env y ejecutar migraciones
php artisan migrate

# Cargar datos de ejemplo (opcional)
php artisan db:seed

# Iniciar servidor de desarrollo
php artisan serve
```

El backend estará disponible en `http://localhost:8000`

### Frontend (Vue)

```bash
cd frontend

# Instalar dependencias
npm install

# Iniciar servidor de desarrollo
npm run dev
```

El frontend estará disponible en `http://localhost:5173`

## Endpoints API

### Categorías
- `GET    /api/categorias` - Listar categorías
- `POST   /api/categorias` - Crear categoría
- `GET    /api/categorias/{id}` - Ver categoría
- `PUT    /api/categorias/{id}` - Actualizar categoría
- `DELETE /api/categorias/{id}` - Eliminar categoría

### Juegos
- `GET    /api/juegos` - Listar juegos (filtros: `buscar`, `categoria_id`, `estado`)
- `POST   /api/juegos` - Crear juego
- `GET    /api/juegos/{id}` - Ver juego con historial de préstamos
- `PUT    /api/juegos/{id}` - Actualizar juego
- `DELETE /api/juegos/{id}` - Eliminar juego

### Préstamos
- `GET    /api/prestamos` - Listar préstamos (filtros: `estado`, `buscar`)
- `POST   /api/prestamos` - Crear préstamo (campo `persona` para nombre libre)
- `GET    /api/prestamos/{id}` - Ver detalle de préstamo
- `PUT    /api/prestamos/{id}` - Actualizar préstamo
- `PATCH  /api/prestamos/{id}/devolver` - Registrar devolución

### BoardGameGeek
- `GET    /api/bgg/collection/{username}` - Colección de un usuario BGG
- `GET    /api/bgg/plays/{username}` - Partidas registradas de un usuario BGG
- `POST   /api/bgg/import` - Importar juegos de BGG a la BBDD local

**Nota:** La API de BGG requiere un token de aplicación. Regístrate en [boardgamegeek.com/applications](https://boardgamegeek.com/applications), crea un token y configúralo como `BGG_API_KEY` en el archivo `.env`.

## Tecnologías

### Backend
- **Laravel 11** - Framework PHP
- **Laravel Sanctum** - Autenticación API
- **Eloquent ORM** - ORM para base de datos

### Frontend
- **Vue 3** - Framework JavaScript (Composition API)
- **Vite** - Build tool
- **Vue Router** - Enrutamiento SPA
- **Pinia** - Gestión de estado
- **Axios** - Cliente HTTP
