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
        $query = Juego::with(['categoria', 'ubicacion.mueble.habitacion', 'propietarios', 'fundas.tipoFunda']);

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

        if ($request->has('propietario_id')) {
            $propietarioId = (int) $request->propietario_id;
            $query->whereHas('propietarios', function ($q) use ($propietarioId) {
                $q->where('propietario_id', $propietarioId);
            });
        }

        if ($request->has('solo_base')) {
            $query->whereNull('juego_base_id');
        }

        if ($request->has('juego_base_id')) {
            $query->where('juego_base_id', $request->juego_base_id);
        }

        if ($request->has('buscar')) {
            $query->where('nombre', 'like', '%' . $request->buscar . '%');
        }

        $perPage = min((int) $request->input('per_page', 15), 1000);
        $juegos = $query->orderBy('nombre')->paginate($perPage);

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
            'fecha_compra' => 'nullable|date',
            'imagen' => 'nullable|string',
            'juego_base_id' => 'nullable|exists:juegos,id',
            'propietario_ids' => 'nullable|array',
            'propietario_ids.*' => 'exists:propietarios,id',
            'fundas' => 'nullable|array',
            'fundas.*.tipo_funda_id' => 'required|distinct|exists:tipos_funda,id',
            'fundas.*.cantidad_cartas' => 'required|integer|min:1|max:65535',
            'fundas.*.enfundadas' => 'boolean',
        ]);

        $propietarioIds = $validated['propietario_ids'] ?? [];
        $fundas = $validated['fundas'] ?? [];
        unset($validated['propietario_ids']);
        unset($validated['fundas']);

        $juego = Juego::create($validated);

        if (!empty($propietarioIds)) {
            $juego->propietarios()->sync($propietarioIds);
        }

        $this->syncFundas($juego, $fundas);

        $juego->load(['categoria', 'ubicacion.mueble.habitacion', 'propietarios', 'fundas.tipoFunda']);

        return response()->json($juego, 201);
    }

    public function show(Juego $juego): JsonResponse
    {
        $juego->load([
            'categoria',
            'ubicacion.mueble.habitacion',
            'prestamos',
            'propietarios',
            'fundas.tipoFunda',
            'juegoBase',
            'expansiones.propietarios',
            'expansiones.ubicacion.mueble.habitacion',
            'expansiones.fundas.tipoFunda',
        ]);

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
            'fecha_compra' => 'nullable|date',
            'imagen' => 'nullable|string',
            'juego_base_id' => 'nullable|exists:juegos,id',
            'propietario_ids' => 'nullable|array',
            'propietario_ids.*' => 'exists:propietarios,id',
            'fundas' => 'nullable|array',
            'fundas.*.tipo_funda_id' => 'required|distinct|exists:tipos_funda,id',
            'fundas.*.cantidad_cartas' => 'required|integer|min:1|max:65535',
            'fundas.*.enfundadas' => 'boolean',
        ]);

        $propietarioIds = $validated['propietario_ids'] ?? null;
        $fundas = $validated['fundas'] ?? null;
        unset($validated['propietario_ids']);
        unset($validated['fundas']);

        $juego->update($validated);

        if ($propietarioIds !== null) {
            $juego->propietarios()->sync($propietarioIds);
        }

        if ($fundas !== null) {
            $this->syncFundas($juego, $fundas);
        }

        $juego->load(['categoria', 'ubicacion.mueble.habitacion', 'propietarios', 'fundas.tipoFunda']);

        return response()->json($juego);
    }

    public function destroy(Juego $juego): JsonResponse
    {
        $juego->delete();

        return response()->json(null, 204);
    }

    private function syncFundas(Juego $juego, array $fundas): void
    {
        $juego->fundas()->delete();

        foreach ($fundas as $funda) {
            $juego->fundas()->create([
                'tipo_funda_id' => $funda['tipo_funda_id'],
                'cantidad_cartas' => $funda['cantidad_cartas'],
                'enfundadas' => $funda['enfundadas'] ?? false,
            ]);
        }
    }
}
