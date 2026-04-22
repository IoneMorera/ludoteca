<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Propietario;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PropietarioController extends Controller
{
    public function index(): JsonResponse
    {
        $propietarios = Propietario::withCount('juegos')
            ->orderBy('nombre')
            ->get();

        return response()->json($propietarios);
    }

    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'nombre' => 'required|string|max:255|unique:propietarios,nombre',
            'bgg_username' => 'nullable|string|max:255',
        ]);

        $propietario = Propietario::create($validated);

        return response()->json($propietario, 201);
    }

    public function show(Propietario $propietario): JsonResponse
    {
        $propietario->load(['juegos.categoria', 'juegos.ubicacion.mueble.habitacion', 'juegos.propietarios']);
        $propietario->loadCount('juegos');

        return response()->json($propietario);
    }

    public function update(Request $request, Propietario $propietario): JsonResponse
    {
        $validated = $request->validate([
            'nombre' => 'required|string|max:255|unique:propietarios,nombre,' . $propietario->id,
            'bgg_username' => 'nullable|string|max:255',
        ]);

        $propietario->update($validated);

        return response()->json($propietario);
    }

    public function destroy(Propietario $propietario): JsonResponse
    {
        if ($propietario->es_principal) {
            return response()->json([
                'message' => 'No se puede eliminar el propietario principal.',
            ], 403);
        }

        $propietario->delete();

        return response()->json(null, 204);
    }

    /**
     * Colección personal: todos los juegos donde este propietario es dueño
     * (solo o compartido).
     */
    public function coleccion(Propietario $propietario): JsonResponse
    {
        $juegos = $propietario->juegos()
            ->with([
                'categoria',
                'ubicacion.mueble.habitacion',
                'propietarios',
                'expansiones.propietarios',
                'juegoBase',
            ])
            ->whereNull('juegos.juego_base_id')
            ->orderBy('nombre')
            ->get();

        return response()->json([
            'propietario' => $propietario,
            'juegos' => $juegos,
            'total' => $juegos->count(),
        ]);
    }

    /**
     * Colección conjunta: unión de todos los juegos de los propietarios indicados.
     */
    public function coleccionConjunta(Request $request): JsonResponse
    {
        $request->validate([
            'propietario_ids' => 'required|array|min:1',
            'propietario_ids.*' => 'exists:propietarios,id',
        ]);

        $ids = $request->input('propietario_ids');
        $propietarios = Propietario::whereIn('id', $ids)->get();

        $juegos = \App\Models\Juego::whereHas('propietarios', function ($q) use ($ids) {
                $q->whereIn('propietario_id', $ids);
            })
            ->whereNull('juego_base_id')
            ->with(['categoria', 'ubicacion.mueble.habitacion', 'propietarios', 'expansiones.propietarios'])
            ->orderBy('nombre')
            ->get();

        return response()->json([
            'propietarios' => $propietarios,
            'juegos' => $juegos,
            'total' => $juegos->count(),
        ]);
    }
}
