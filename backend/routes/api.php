<?php

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\BggController;
use App\Http\Controllers\Api\CategoriaController;
use App\Http\Controllers\Api\HabitacionController;
use App\Http\Controllers\Api\JuegoController;
use App\Http\Controllers\Api\MuebleController;
use App\Http\Controllers\Api\PrestamoController;
use App\Http\Controllers\Api\PropietarioController;
use App\Http\Controllers\Api\UbicacionController;
use App\Http\Middleware\InitializeTenancyByUser;
use App\Models\Juego;
use App\Models\Prestamo;
use Illuminate\Routing\Middleware\SubstituteBindings;
use Illuminate\Support\Facades\Route;

// --- Rutas públicas (central) ---
Route::post('register', [AuthController::class, 'register']);
Route::post('login', [AuthController::class, 'login']);
Route::post('mobile/login', [AuthController::class, 'mobileLogin']);

// --- Rutas protegidas ---
Route::middleware('auth:sanctum')->group(function () {
    Route::post('logout', [AuthController::class, 'logout']);
    Route::post('mobile/logout', [AuthController::class, 'mobileLogout']);
    Route::get('user', [AuthController::class, 'user']);

    // --- Rutas con tenancy (BBDD del usuario) ---
    Route::middleware([InitializeTenancyByUser::class, SubstituteBindings::class])->group(function () {
        Route::get('stats', function () {
            return response()->json([
                'totalJuegos' => Juego::whereNull('juego_base_id')->count(),
                'juegosDisponibles' => Juego::whereNull('juego_base_id')->where('estado', 'disponible')->count(),
                'prestamosActivos' => Prestamo::where('estado', 'activo')->count(),
                'totalExpansiones' => Juego::whereNotNull('juego_base_id')->count(),
            ]);
        });

        Route::get('bgg/search', [BggController::class, 'search']);
        Route::get('bgg/collection/{username}', [BggController::class, 'collection']);
        Route::get('bgg/expansions/{username}', [BggController::class, 'expansions']);
        Route::get('bgg/plays/{username}', [BggController::class, 'plays']);
        Route::post('bgg/import', [BggController::class, 'import']);
        Route::post('bgg/import-expansions', [BggController::class, 'importExpansions']);
        Route::post('bgg/import-images', [BggController::class, 'importImages']);

        Route::apiResource('categorias', CategoriaController::class);
        Route::apiResource('juegos', JuegoController::class);
        Route::apiResource('habitaciones', HabitacionController::class)->except(['show']);
        Route::apiResource('muebles', MuebleController::class)->except(['show']);

        Route::apiResource('prestamos', PrestamoController::class)->except(['destroy']);
        Route::patch('prestamos/{prestamo}/devolver', [PrestamoController::class, 'devolver'])
            ->name('prestamos.devolver');

        Route::get('ubicaciones', [UbicacionController::class, 'index']);
        Route::post('ubicaciones', [UbicacionController::class, 'store']);

        Route::apiResource('propietarios', PropietarioController::class);
        Route::get('propietarios/{propietario}/coleccion', [PropietarioController::class, 'coleccion']);
        Route::post('colecciones/conjunta', [PropietarioController::class, 'coleccionConjunta']);
    });
});
