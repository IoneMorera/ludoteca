<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Juego;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class JuegoController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $query = Juego::with(['categoria', 'ubicacion.mueble.habitacion']);

        if ($request->has('categoria_id')) {
            $query->where('categoria_id', $request->categoria_id);
        }

        if ($request->has('estado')) {
            $query->where('estado', $request->estado);
        }

        if ($request->has('habitacion_id')) {
            $habitacionId = (int) $request->habitacion_id;
            $query->whereHas('ubicacion.mueble', function ($q) use ($habitacionId) {
                $q->where('habitacion_id', $habitacionId);
            });
        }

        if ($request->has('buscar')) {
            $query->where('nombre', 'like', '%' . $request->buscar . '%');
        }

        $juegos = $query->orderBy('nombre')->paginate(15);

        return response()->json($juegos);
    }

    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'nombre' => 'required|string|max:255',
            'descripcion' => 'nullable|string',
            'edad_minima' => 'nullable|integer|min:0',
            'edad_maxima' => 'nullable|integer|min:0',
            'num_jugadores_min' => 'nullable|integer|min:1',
            'num_jugadores_max' => 'nullable|integer|min:1',
            'categoria_id' => 'required|exists:categorias,id',
            'ubicacion_id' => 'nullable|exists:ubicaciones,id',
            'estado' => 'in:disponible,prestado,reparacion,baja',
            'imagen' => 'nullable|string',
        ]);

        $juego = Juego::create($validated);
        $juego->load(['categoria', 'ubicacion.mueble.habitacion']);

        return response()->json($juego, 201);
    }

    public function show(Juego $juego): JsonResponse
    {
        $juego->load(['categoria', 'ubicacion.mueble.habitacion', 'prestamos']);

        return response()->json($juego);
    }

    public function update(Request $request, Juego $juego): JsonResponse
    {
        $validated = $request->validate([
            'nombre' => 'required|string|max:255',
            'descripcion' => 'nullable|string',
            'edad_minima' => 'nullable|integer|min:0',
            'edad_maxima' => 'nullable|integer|min:0',
            'num_jugadores_min' => 'nullable|integer|min:1',
            'num_jugadores_max' => 'nullable|integer|min:1',
            'categoria_id' => 'required|exists:categorias,id',
            'ubicacion_id' => 'nullable|exists:ubicaciones,id',
            'estado' => 'in:disponible,prestado,reparacion,baja',
            'imagen' => 'nullable|string',
        ]);

        $juego->update($validated);
        $juego->load(['categoria', 'ubicacion.mueble.habitacion']);

        return response()->json($juego);
    }

    public function destroy(Juego $juego): JsonResponse
    {
        $juego->delete();

        return response()->json(null, 204);
    }
}
