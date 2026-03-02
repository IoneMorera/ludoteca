<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Mueble;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class MuebleController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $query = Mueble::withCount('ubicaciones')->with('habitacion')->orderBy('nombre');

        if ($request->filled('habitacion_id')) {
            $query->where('habitacion_id', $request->integer('habitacion_id'));
        }

        return response()->json($query->get());
    }

    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'habitacion_id' => ['required', 'exists:habitaciones,id'],
            'nombre' => ['required', 'string', 'max:255'],
        ]);

        $mueble = Mueble::create($validated);

        return response()->json($mueble->load('habitacion'), 201);
    }

    public function update(Request $request, Mueble $mueble): JsonResponse
    {
        $validated = $request->validate([
            'habitacion_id' => ['required', 'exists:habitaciones,id'],
            'nombre' => ['required', 'string', 'max:255'],
        ]);

        $mueble->update($validated);

        return response()->json($mueble->load('habitacion'));
    }

    public function destroy(Mueble $mueble): JsonResponse
    {
        $mueble->delete();

        return response()->json(null, 204);
    }
}

