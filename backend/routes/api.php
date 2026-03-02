<?php

use App\Http\Controllers\Api\BggController;
use App\Http\Controllers\Api\CategoriaController;
use App\Http\Controllers\Api\HabitacionController;
use App\Http\Controllers\Api\JuegoController;
use App\Http\Controllers\Api\MuebleController;
use App\Http\Controllers\Api\PrestamoController;
use App\Http\Controllers\Api\UbicacionController;
use App\Models\Habitacion;
use App\Models\Mueble;
use App\Models\Juego;
use App\Models\Prestamo;
use Illuminate\Support\Facades\Route;

Route::get('stats', function () {
    return response()->json([
        'totalJuegos' => Juego::count(),
        'juegosDisponibles' => Juego::where('estado', 'disponible')->count(),
        'prestamosActivos' => Prestamo::where('estado', 'activo')->count(),
    ]);
});

Route::get('bgg/collection/{username}', [BggController::class, 'collection']);
Route::get('bgg/plays/{username}', [BggController::class, 'plays']);
Route::post('bgg/import', [BggController::class, 'import']);

Route::apiResource('categorias', CategoriaController::class);
Route::apiResource('juegos', JuegoController::class);
Route::apiResource('habitaciones', HabitacionController::class)->except(['show']);
Route::apiResource('muebles', MuebleController::class)->except(['show']);

Route::apiResource('prestamos', PrestamoController::class)->except(['destroy']);
Route::patch('prestamos/{prestamo}/devolver', [PrestamoController::class, 'devolver'])
    ->name('prestamos.devolver');

Route::get('ubicaciones', [UbicacionController::class, 'index']);
Route::post('ubicaciones', [UbicacionController::class, 'store']);
