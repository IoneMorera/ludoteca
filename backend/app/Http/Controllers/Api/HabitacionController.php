<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Habitacion;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class HabitacionController extends Controller
{
    public function index(): JsonResponse
    {
        $habitaciones = Habitacion::withCount('muebles')
            ->withCount(['muebles as juegos_count' => function ($query) {
                $query->join('ubicaciones', 'ubicaciones.mueble_id', '=', 'muebles.id')
                    ->join('juegos', 'juegos.ubicacion_id', '=', 'ubicaciones.id');
            }])
            ->orderBy('nombre')
            ->get();

        return response()->json($habitaciones);
    }

    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'nombre' => ['required', 'string', 'max:255', 'unique:habitaciones,nombre'],
        ]);

        $habitacion = Habitacion::create($validated);

        return response()->json($habitacion, 201);
    }

    public function update(Request $request, Habitacion $habitacione): JsonResponse
    {
        $validated = $request->validate([
            'nombre' => ['required', 'string', 'max:255', 'unique:habitaciones,nombre,' . $habitacione->id],
        ]);

        $habitacione->update($validated);

        return response()->json($habitacione);
    }

    public function destroy(Habitacion $habitacione): JsonResponse
    {
        $habitacione->delete();

        return response()->json(null, 204);
    }
}

