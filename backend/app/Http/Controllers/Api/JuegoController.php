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
        $query = Juego::with(['categorias', 'ubicacion.mueble.habitacion', 'propietarios', 'fundas.tipoFunda']);

        if ($request->has('categoria_id')) {
            $catId = (int) $request->categoria_id;
            $query->whereHas('categorias', fn ($q) => $q->where('categorias.id', $catId));
        }

        if ($request->boolean('es_expansion', false)) {
            $query->where('es_expansion', true);
        } elseif ($request->has('solo_base')) {
            $query->where('es_expansion', false);
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

        if ($request->has('solo_base') && !$request->has('es_expansion')) {
            $query->where('es_expansion', false);
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
            'categoria_ids' => 'required|array|min:1',
            'categoria_ids.*' => 'exists:categorias,id',
            'ubicacion_id' => 'nullable|exists:ubicaciones,id',
            'estado' => 'in:disponible,en_venta,vendido',
            'fecha_compra' => 'nullable|date',
            'imagen' => 'nullable|string',
            'juego_base_id' => 'nullable|exists:juegos,id',
            'es_expansion' => 'boolean',
            'autojugable' => 'boolean',
            'idiomas' => 'nullable|array',
            'idiomas.*' => 'string',
            'idioma_otro' => 'nullable|string|max:255',
            'independiente_idioma' => 'boolean',
            'tradumaquetado' => 'boolean',
            'tradumaquetado_parcial' => 'boolean',
            'tradumaquetado_parcial_notas' => 'nullable|string',
            'varias_copias' => 'boolean',
            'sin_abrir' => 'boolean',
            'print_and_play' => 'boolean',
            'propietario_ids' => 'nullable|array',
            'propietario_ids.*' => 'exists:propietarios,id',
            'propietario_ubicaciones' => 'nullable|array',
            'propietario_ubicaciones.*.propietario_id' => 'exists:propietarios,id',
            'propietario_ubicaciones.*.ubicacion_id' => 'nullable|exists:ubicaciones,id',
            'fundas' => 'nullable|array',
            'fundas.*.tipo_funda_id' => 'required|distinct|exists:tipos_funda,id',
            'fundas.*.cantidad_cartas' => 'required|integer|min:1|max:65535',
            'fundas.*.enfundadas' => 'boolean',
        ]);

        $categoriaIds = $validated['categoria_ids'];
        $propietarioIds = $validated['propietario_ids'] ?? [];
        $propietarioUbicaciones = $validated['propietario_ubicaciones'] ?? [];
        $fundas = $validated['fundas'] ?? [];
        unset($validated['categoria_ids'], $validated['propietario_ids'], $validated['propietario_ubicaciones'], $validated['fundas']);

        $juego = Juego::create($validated);

        $juego->categorias()->sync($categoriaIds);
        $this->syncPropietarios($juego, $propietarioIds, $propietarioUbicaciones);
        $this->syncFundas($juego, $fundas);

        $juego->load(['categorias', 'ubicacion.mueble.habitacion', 'propietarios', 'fundas.tipoFunda']);

        return response()->json($juego, 201);
    }

    public function show(Juego $juego): JsonResponse
    {
        $juego->load([
            'categorias',
            'ubicacion.mueble.habitacion',
            'prestamos',
            'propietarios',
            'fundas.tipoFunda',
            'juegoBase',
            'expansiones.propietarios',
            'expansiones.categorias',
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
            'categoria_ids' => 'nullable|array|min:1',
            'categoria_ids.*' => 'exists:categorias,id',
            'ubicacion_id' => 'nullable|exists:ubicaciones,id',
            'estado' => 'in:disponible,en_venta,vendido',
            'fecha_compra' => 'nullable|date',
            'imagen' => 'nullable|string',
            'juego_base_id' => 'nullable|exists:juegos,id',
            'es_expansion' => 'boolean',
            'autojugable' => 'boolean',
            'idiomas' => 'nullable|array',
            'idiomas.*' => 'string',
            'idioma_otro' => 'nullable|string|max:255',
            'independiente_idioma' => 'boolean',
            'tradumaquetado' => 'boolean',
            'tradumaquetado_parcial' => 'boolean',
            'tradumaquetado_parcial_notas' => 'nullable|string',
            'varias_copias' => 'boolean',
            'sin_abrir' => 'boolean',
            'print_and_play' => 'boolean',
            'propietario_ids' => 'nullable|array',
            'propietario_ids.*' => 'exists:propietarios,id',
            'propietario_ubicaciones' => 'nullable|array',
            'propietario_ubicaciones.*.propietario_id' => 'exists:propietarios,id',
            'propietario_ubicaciones.*.ubicacion_id' => 'nullable|exists:ubicaciones,id',
            'fundas' => 'nullable|array',
            'fundas.*.tipo_funda_id' => 'required|distinct|exists:tipos_funda,id',
            'fundas.*.cantidad_cartas' => 'required|integer|min:1|max:65535',
            'fundas.*.enfundadas' => 'boolean',
        ]);

        $categoriaIds = $validated['categoria_ids'] ?? null;
        $propietarioIds = $validated['propietario_ids'] ?? null;
        $propietarioUbicaciones = $validated['propietario_ubicaciones'] ?? [];
        $fundas = $validated['fundas'] ?? null;
        unset($validated['categoria_ids'], $validated['propietario_ids'], $validated['propietario_ubicaciones'], $validated['fundas']);

        $juego->update($validated);

        if ($categoriaIds !== null) {
            $juego->categorias()->sync($categoriaIds);
        }

        if ($propietarioIds !== null) {
            $this->syncPropietarios($juego, $propietarioIds, $propietarioUbicaciones);
        }

        if ($fundas !== null) {
            $this->syncFundas($juego, $fundas);
        }

        $juego->load(['categorias', 'ubicacion.mueble.habitacion', 'propietarios', 'fundas.tipoFunda']);

        return response()->json($juego);
    }

    public function destroy(Juego $juego): JsonResponse
    {
        $juego->delete();

        return response()->json(null, 204);
    }

    public function uploadImage(Request $request): JsonResponse
    {
        $request->validate([
            'image' => 'required|image|max:5120',
        ]);

        $file = $request->file('image');
        $extension = $file->getClientOriginalExtension() ?: 'jpg';
        $filename = 'juego_' . time() . '_' . uniqid() . '.' . $extension;

        if (config('filesystems.disks.r2.key')) {
            $tenantId = tenant('id') ?? auth()->id();
            $path = "tenants/{$tenantId}/juegos/{$filename}";
            $file->storeAs(dirname($path), basename($path), 'r2');
            $url = config('filesystems.disks.r2.url') . '/' . $path;
        } else {
            $path = $file->storeAs('juegos', $filename, 'public');
            $url = '/storage/' . $path;
        }

        return response()->json(['url' => $url]);
    }

    private function syncPropietarios(Juego $juego, array $propietarioIds, array $propietarioUbicaciones): void
    {
        $syncData = [];
        $ubicMap = collect($propietarioUbicaciones)->keyBy('propietario_id');

        foreach ($propietarioIds as $propId) {
            $ubicacionId = $ubicMap->get($propId)['ubicacion_id'] ?? null;
            $syncData[$propId] = ['ubicacion_id' => $ubicacionId];
        }

        $juego->propietarios()->sync($syncData);
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
