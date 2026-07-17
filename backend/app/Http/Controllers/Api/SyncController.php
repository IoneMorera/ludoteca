<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Categoria;
use App\Models\Habitacion;
use App\Models\Juego;
use App\Models\JuegoFunda;
use App\Models\JuegoCategoriaPivot;
use App\Models\JuegoPropietarioFunda;
use App\Models\JuegoPropietarioPivot;
use App\Models\Mueble;
use App\Models\Propietario;
use App\Models\TipoFunda;
use App\Models\Tombstone;
use App\Models\Ubicacion;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

class SyncController extends Controller
{
    /**
     * Returns full data for all synced tables so the mobile client
     * can compare field-by-field against its local DB.
     */
    public function verify(): JsonResponse
    {
        $tables = [
            'categorias' => $this->fetchCategorias(null),
            'propietarios' => $this->fetchPropietarios(null),
            'habitaciones' => $this->fetchHabitaciones(null),
            'muebles' => $this->fetchMuebles(null),
            'ubicaciones' => $this->fetchUbicaciones(null),
            'tipos_funda' => $this->fetchTiposFunda(null),
            'juegos' => $this->fetchJuegos(null),
            'juego_fundas' => $this->fetchJuegoFundas(null),
            'juego_propietario' => $this->fetchJuegoPropietario(null),
            'juego_propietario_fundas' => $this->fetchJuegoPropietarioFundas(null),
            'juego_categoria' => $this->fetchJuegoCategoria(null),
        ];

        return response()->json([
            'tables' => (object) $tables,
            'server_now' => now()->toIso8601String(),
        ]);
    }

    /**
     * Returns all rows of the synced tables modified since `since`,
     * plus tombstones for deletes. If `since` is null, returns a full snapshot.
     */
    public function snapshot(Request $request): JsonResponse
    {
        $since = $this->parseSince($request->input('since'));
        $serverNow = now();

        $tables = [
            'categorias' => $this->fetchCategorias($since),
            'propietarios' => $this->fetchPropietarios($since),
            'habitaciones' => $this->fetchHabitaciones($since),
            'muebles' => $this->fetchMuebles($since),
            'ubicaciones' => $this->fetchUbicaciones($since),
            'tipos_funda' => $this->fetchTiposFunda($since),
            'juegos' => $this->fetchJuegos($since),
            'juego_fundas' => $this->fetchJuegoFundas($since),
            'juego_propietario' => $this->fetchJuegoPropietario($since),
            'juego_propietario_fundas' => $this->fetchJuegoPropietarioFundas($since),
            'juego_categoria' => $this->fetchJuegoCategoria($since),
        ];

        $deleted = $this->fetchTombstones($since);

        return response()->json([
            'server_now' => $serverNow->toIso8601String(),
            'since' => $since?->toIso8601String(),
            'tables' => (object) $tables,
            'deleted' => (object) $deleted,
        ]);
    }

    /**
     * Receives a batch of operations from a client and applies them.
     *
     * Body: {
     *   operations: [
     *     {
     *       client_op_id: string,
     *       table: string,
     *       action: 'create'|'update'|'delete',
     *       server_id?: int,
     *       base_updated_at?: ISO,
     *       data?: object
     *     }
     *   ]
     * }
     */
    public function push(Request $request): JsonResponse
    {
        $request->validate([
            'operations' => 'required|array|min:1',
            'operations.*.client_op_id' => 'required|string',
            'operations.*.table' => 'required|string',
            'operations.*.action' => 'required|in:create,update,delete',
        ]);

        $results = [];

        foreach ($request->input('operations') as $op) {
            try {
                $result = DB::transaction(function () use ($op) {
                    return $this->applyOperation($op);
                });
                $results[] = $result;
            } catch (\Throwable $e) {
                Log::warning('sync.push operation failed', [
                    'op' => $op,
                    'error' => $e->getMessage(),
                ]);
                $results[] = [
                    'client_op_id' => $op['client_op_id'],
                    'status' => 'error',
                    'error' => $e->getMessage(),
                ];
            }
        }

        return response()->json([
            'results' => $results,
            'server_now' => now()->toIso8601String(),
        ]);
    }

    private function applyOperation(array $op): array
    {
        $table = $op['table'];
        $action = $op['action'];
        $clientOpId = $op['client_op_id'];
        $data = $op['data'] ?? [];
        $serverId = $op['server_id'] ?? null;
        $baseUpdatedAt = $this->parseSince($op['base_updated_at'] ?? null);

        $modelClass = $this->resolveModel($table);

        if ($action === 'delete') {
            if (!$serverId) {
                if ($table === 'juego_categoria') {
                    $juegoId = $data['juego_id'] ?? null;
                    $categoriaId = $data['categoria_id'] ?? null;
                    if ($juegoId && $categoriaId) {
                        $model = JuegoCategoriaPivot::query()
                            ->where('juego_id', (int) $juegoId)
                            ->where('categoria_id', (int) $categoriaId)
                            ->first();
                        if ($model) {
                            $resolvedId = (int) $model->getKey();
                            $model->delete();
                            return [
                                'client_op_id' => $clientOpId,
                                'status' => 'ok',
                                'server_id' => $resolvedId,
                            ];
                        }

                        return [
                            'client_op_id' => $clientOpId,
                            'status' => 'not_found',
                        ];
                    }
                }

                return [
                    'client_op_id' => $clientOpId,
                    'status' => 'error',
                    'error' => 'server_id required for delete',
                ];
            }
            $model = $modelClass::find($serverId);
            if ($model) {
                $model->delete();
            } else {
                Tombstone::record($table, (int) $serverId);
            }
            return [
                'client_op_id' => $clientOpId,
                'status' => 'ok',
                'server_id' => (int) $serverId,
            ];
        }

        $sanitized = $this->sanitizeData($table, $data);

        if ($action === 'create') {
            $model = $modelClass::create($sanitized);
            return [
                'client_op_id' => $clientOpId,
                'status' => 'ok',
                'server_id' => (int) $model->getKey(),
                'updated_at' => $model->updated_at?->toIso8601String(),
                'record' => $this->serializeRecord($table, $model),
            ];
        }

        // update
        if (!$serverId) {
            return [
                'client_op_id' => $clientOpId,
                'status' => 'error',
                'error' => 'server_id required for update',
            ];
        }

        $model = $modelClass::find($serverId);
        if (!$model) {
            return [
                'client_op_id' => $clientOpId,
                'status' => 'not_found',
            ];
        }

        if ($baseUpdatedAt && $model->updated_at && $model->updated_at->gt($baseUpdatedAt)) {
            return [
                'client_op_id' => $clientOpId,
                'status' => 'conflict_server_wins',
                'server_id' => (int) $model->getKey(),
                'updated_at' => $model->updated_at->toIso8601String(),
                'record' => $this->serializeRecord($table, $model),
            ];
        }

        $model->fill($sanitized);
        $model->save();

        return [
            'client_op_id' => $clientOpId,
            'status' => 'ok',
            'server_id' => (int) $model->getKey(),
            'updated_at' => $model->updated_at?->toIso8601String(),
            'record' => $this->serializeRecord($table, $model),
        ];
    }

    private function sanitizeData(string $table, array $data): array
    {
        $allowed = match ($table) {
            'juegos' => [
                'nombre', 'descripcion', 'edad_minima', 'edad_maxima',
                'num_jugadores_min', 'num_jugadores_max', 'categoria_id',
                'ubicacion_id', 'estado', 'fecha_compra', 'imagen', 'bgg_id',
                'juego_base_id', 'no_enfundar', 'es_expansion', 'idiomas',
                'idioma_otro', 'independiente_idioma', 'tradumaquetado',
                'tradumaquetado_parcial', 'tradumaquetado_parcial_notas',
                'varias_copias', 'precio', 'en_caja_base',
                'sin_abrir', 'print_and_play',
            ],
            'categorias' => ['nombre', 'descripcion'],
            'propietarios' => ['nombre', 'bgg_username', 'es_principal'],
            'habitaciones' => ['nombre'],
            'muebles' => ['habitacion_id', 'nombre'],
            'ubicaciones' => ['mueble_id', 'nombre'],
            'tipos_funda' => ['nombre', 'ancho_mm', 'alto_mm', 'descripcion'],
            'juego_fundas' => ['juego_id', 'tipo_funda_id', 'cantidad_cartas', 'enfundadas'],
            'juego_propietario' => [
                'juego_id', 'propietario_id', 'ubicacion_id', 'es_principal',
                'estado', 'fecha_compra', 'no_enfundar', 'idiomas', 'idioma_otro',
                'independiente_idioma', 'tradumaquetado', 'tradumaquetado_parcial',
                'tradumaquetado_parcial_notas',
            ],
            'juego_propietario_fundas' => [
                'juego_propietario_id', 'tipo_funda_id', 'cantidad_cartas', 'enfundadas',
            ],
            'juego_categoria' => ['juego_id', 'categoria_id'],
            default => [],
        };

        return array_intersect_key($data, array_flip($allowed));
    }

    private function resolveModel(string $table): string
    {
        return match ($table) {
            'juegos' => Juego::class,
            'categorias' => Categoria::class,
            'propietarios' => Propietario::class,
            'habitaciones' => Habitacion::class,
            'muebles' => Mueble::class,
            'ubicaciones' => Ubicacion::class,
            'tipos_funda' => TipoFunda::class,
            'juego_fundas' => JuegoFunda::class,
            'juego_propietario' => JuegoPropietarioPivot::class,
            'juego_propietario_fundas' => JuegoPropietarioFunda::class,
            'juego_categoria' => JuegoCategoriaPivot::class,
            default => throw new \InvalidArgumentException("Unknown table: {$table}"),
        };
    }

    private function serializeRecord(string $table, $model): array
    {
        return array_merge($model->toArray(), [
            'id' => (int) $model->getKey(),
            'updated_at' => $model->updated_at?->toIso8601String(),
            'created_at' => $model->created_at?->toIso8601String(),
        ]);
    }

    private function parseSince($since): ?Carbon
    {
        if (!$since) {
            return null;
        }
        try {
            return Carbon::parse($since);
        } catch (\Throwable $e) {
            return null;
        }
    }

    private function fetchCategorias(?Carbon $since): array
    {
        return Categoria::query()
            ->when($since, fn ($q) => $q->where('updated_at', '>', $since))
            ->get()
            ->map(fn ($c) => [
                'id' => $c->id,
                'nombre' => $c->nombre,
                'descripcion' => $c->descripcion,
                'created_at' => $c->created_at?->toIso8601String(),
                'updated_at' => $c->updated_at?->toIso8601String(),
            ])->all();
    }

    private function fetchPropietarios(?Carbon $since): array
    {
        return Propietario::query()
            ->when($since, fn ($q) => $q->where('updated_at', '>', $since))
            ->get()
            ->map(fn ($p) => [
                'id' => $p->id,
                'nombre' => $p->nombre,
                'bgg_username' => $p->bgg_username,
                'es_principal' => (bool) $p->es_principal,
                'created_at' => $p->created_at?->toIso8601String(),
                'updated_at' => $p->updated_at?->toIso8601String(),
            ])->all();
    }

    private function fetchHabitaciones(?Carbon $since): array
    {
        return Habitacion::query()
            ->when($since, fn ($q) => $q->where('updated_at', '>', $since))
            ->get()
            ->map(fn ($h) => [
                'id' => $h->id,
                'nombre' => $h->nombre,
                'created_at' => $h->created_at?->toIso8601String(),
                'updated_at' => $h->updated_at?->toIso8601String(),
            ])->all();
    }

    private function fetchMuebles(?Carbon $since): array
    {
        return Mueble::query()
            ->when($since, fn ($q) => $q->where('updated_at', '>', $since))
            ->get()
            ->map(fn ($m) => [
                'id' => $m->id,
                'habitacion_id' => $m->habitacion_id,
                'nombre' => $m->nombre,
                'created_at' => $m->created_at?->toIso8601String(),
                'updated_at' => $m->updated_at?->toIso8601String(),
            ])->all();
    }

    private function fetchUbicaciones(?Carbon $since): array
    {
        return Ubicacion::query()
            ->when($since, fn ($q) => $q->where('updated_at', '>', $since))
            ->get()
            ->map(fn ($u) => [
                'id' => $u->id,
                'mueble_id' => $u->mueble_id,
                'nombre' => $u->nombre,
                'created_at' => $u->created_at?->toIso8601String(),
                'updated_at' => $u->updated_at?->toIso8601String(),
            ])->all();
    }

    private function fetchTiposFunda(?Carbon $since): array
    {
        return TipoFunda::query()
            ->when($since, fn ($q) => $q->where('updated_at', '>', $since))
            ->get()
            ->map(fn ($t) => [
                'id' => $t->id,
                'nombre' => $t->nombre,
                'ancho_mm' => $t->ancho_mm,
                'alto_mm' => $t->alto_mm,
                'descripcion' => $t->descripcion,
                'created_at' => $t->created_at?->toIso8601String(),
                'updated_at' => $t->updated_at?->toIso8601String(),
            ])->all();
    }

    private function fetchJuegos(?Carbon $since): array
    {
        return Juego::query()
            ->when($since, fn ($q) => $q->where('updated_at', '>', $since))
            ->get()
            ->map(fn ($j) => [
                'id' => $j->id,
                'nombre' => $j->nombre,
                'descripcion' => $j->descripcion,
                'edad_minima' => $j->edad_minima,
                'edad_maxima' => $j->edad_maxima,
                'num_jugadores_min' => $j->num_jugadores_min,
                'num_jugadores_max' => $j->num_jugadores_max,
                'categoria_id' => $j->categoria_id,
                'ubicacion_id' => $j->ubicacion_id,
                'estado' => $j->estado,
                'fecha_compra' => $j->fecha_compra?->format('Y-m-d'),
                'imagen' => $j->imagen,
                'bgg_id' => $j->bgg_id,
                'juego_base_id' => $j->juego_base_id,
                'no_enfundar' => (bool) $j->no_enfundar,
                'es_expansion' => (bool) $j->es_expansion,
                'idiomas' => $j->idiomas,
                'idioma_otro' => $j->idioma_otro,
                'independiente_idioma' => (bool) $j->independiente_idioma,
                'tradumaquetado' => (bool) $j->tradumaquetado,
                'tradumaquetado_parcial' => (bool) $j->tradumaquetado_parcial,
                'tradumaquetado_parcial_notas' => $j->tradumaquetado_parcial_notas,
                'varias_copias' => (bool) $j->varias_copias,
                'precio' => $j->precio,
                'en_caja_base' => (bool) $j->en_caja_base,
                'sin_abrir' => (bool) $j->sin_abrir,
                'print_and_play' => (bool) $j->print_and_play,
                'created_at' => $j->created_at?->toIso8601String(),
                'updated_at' => $j->updated_at?->toIso8601String(),
            ])->all();
    }

    private function fetchJuegoFundas(?Carbon $since): array
    {
        return JuegoFunda::query()
            ->when($since, fn ($q) => $q->where('updated_at', '>', $since))
            ->get()
            ->map(fn ($f) => [
                'id' => $f->id,
                'juego_id' => $f->juego_id,
                'tipo_funda_id' => $f->tipo_funda_id,
                'cantidad_cartas' => $f->cantidad_cartas,
                'enfundadas' => (bool) $f->enfundadas,
                'created_at' => $f->created_at?->toIso8601String(),
                'updated_at' => $f->updated_at?->toIso8601String(),
            ])->all();
    }

    private function fetchJuegoPropietario(?Carbon $since): array
    {
        return DB::table('juego_propietario')
            ->when($since, fn ($q) => $q->where('updated_at', '>', $since))
            ->get()
            ->map(fn ($row) => [
                'id' => $row->id,
                'juego_id' => $row->juego_id,
                'propietario_id' => $row->propietario_id,
                'ubicacion_id' => $row->ubicacion_id ?? null,
                'es_principal' => (bool) ($row->es_principal ?? false),
                'estado' => $row->estado ?? null,
                'fecha_compra' => $row->fecha_compra ?? null,
                'no_enfundar' => (bool) ($row->no_enfundar ?? false),
                'idiomas' => $row->idiomas ? json_decode($row->idiomas, true) : null,
                'idioma_otro' => $row->idioma_otro ?? null,
                'independiente_idioma' => (bool) ($row->independiente_idioma ?? false),
                'tradumaquetado' => (bool) ($row->tradumaquetado ?? false),
                'tradumaquetado_parcial' => (bool) ($row->tradumaquetado_parcial ?? false),
                'tradumaquetado_parcial_notas' => $row->tradumaquetado_parcial_notas ?? null,
                'created_at' => $row->created_at,
                'updated_at' => $row->updated_at,
            ])->all();
    }

    private function fetchJuegoPropietarioFundas(?Carbon $since): array
    {
        return JuegoPropietarioFunda::query()
            ->when($since, fn ($q) => $q->where('updated_at', '>', $since))
            ->get()
            ->map(fn ($f) => [
                'id' => $f->id,
                'juego_propietario_id' => $f->juego_propietario_id,
                'tipo_funda_id' => $f->tipo_funda_id,
                'cantidad_cartas' => $f->cantidad_cartas,
                'enfundadas' => (bool) $f->enfundadas,
                'created_at' => $f->created_at?->toIso8601String(),
                'updated_at' => $f->updated_at?->toIso8601String(),
            ])->all();
    }

    private function fetchJuegoCategoria(?Carbon $since): array
    {
        return DB::table('juego_categoria')
            ->when($since, fn ($q) => $q->where('updated_at', '>', $since))
            ->get()
            ->map(fn ($row) => [
                'id' => $row->id,
                'juego_id' => $row->juego_id,
                'categoria_id' => $row->categoria_id,
                'created_at' => $row->created_at,
                'updated_at' => $row->updated_at,
            ])->all();
    }

    private function fetchTombstones(?Carbon $since): array
    {
        $query = Tombstone::query();
        if ($since) {
            $query->where('deleted_at', '>', $since);
        }
        return $query->get()
            ->groupBy('table_name')
            ->map(fn ($items) => $items->pluck('record_id')->map(fn ($id) => (int) $id)->all())
            ->all();
    }
}
