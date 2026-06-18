<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Categoria;
use App\Models\Juego;
use App\Models\Propietario;
use Illuminate\Http\Client\Pool;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;

class BggController extends Controller
{
    private const BGG_API_URL = 'https://boardgamegeek.com/xmlapi2';
    private const MAX_RETRIES = 5;
    private const RETRY_DELAY_SECONDS = 2;
    private const IMAGE_USER_AGENT = 'Ludoteca/1.0 (BoardGameGeek Integration)';
    private const IMAGE_TIMEOUT = 20;

    public function collection(string $username): JsonResponse
    {
        $apiKey = config('services.bgg.api_key');
        if (empty($apiKey)) {
            return response()->json([
                'message' => 'BGG_API_KEY no configurada.',
            ], 500);
        }

        $response = $this->fetchWithRetry(self::BGG_API_URL . '/collection', [
            'username' => $username,
            'own' => 1,
            'stats' => 1,
            'subtype' => 'boardgame',
            'excludesubtype' => 'boardgameexpansion',
        ], $apiKey);

        if (!$response) {
            return response()->json([
                'message' => 'BGG está procesando la colección, inténtalo de nuevo en unos segundos.',
            ], 202);
        }

        if ($response->failed()) {
            return response()->json([
                'message' => 'Error al obtener datos de BGG.',
            ], $response->status());
        }

        $games = $this->parseCollectionXml($response->body());

        return response()->json([
            'username' => $username,
            'total' => count($games),
            'games' => $games,
        ]);
    }

    public function expansions(string $username): JsonResponse
    {
        $apiKey = config('services.bgg.api_key');
        if (empty($apiKey)) {
            return response()->json([
                'message' => 'BGG_API_KEY no configurada.',
            ], 500);
        }

        $response = $this->fetchWithRetry(self::BGG_API_URL . '/collection', [
            'username' => $username,
            'own' => 1,
            'stats' => 1,
            'subtype' => 'boardgameexpansion',
        ], $apiKey);

        if (!$response) {
            return response()->json([
                'message' => 'BGG está procesando la colección, inténtalo de nuevo en unos segundos.',
            ], 202);
        }

        if ($response->failed()) {
            return response()->json([
                'message' => 'Error al obtener expansiones de BGG.',
            ], $response->status());
        }

        $expansions = $this->parseCollectionXml($response->body());

        return response()->json([
            'username' => $username,
            'total' => count($expansions),
            'expansions' => $expansions,
        ]);
    }

    public function import(Request $request): JsonResponse
    {
        $request->validate([
            'games' => 'required|array|min:1',
            'games.*.bgg_id' => 'required|integer',
            'games.*.name' => 'required|string',
            'bgg_username' => 'nullable|string',
        ]);

        try {
            $categoria = Categoria::firstOrCreate(
                ['nombre' => 'Importado BGG'],
                ['descripcion' => 'Juegos importados desde BoardGameGeek']
            );

            $propietario = $this->resolveOwner($request->input('bgg_username'));

            $games = $request->input('games');
            $bggIds = array_values(array_unique(array_map(fn ($g) => (int) $g['bgg_id'], $games)));

            $existingBggIds = Juego::whereIn('bgg_id', $bggIds)->pluck('bgg_id')->all();
            $existingBggIdsSet = array_flip($existingBggIds);

            $now = now();
            $rowsByBggId = [];
            $imagesPending = [];

            foreach ($games as $game) {
                $bggId = (int) $game['bgg_id'];
                if (isset($existingBggIdsSet[$bggId]) || isset($rowsByBggId[$bggId])) {
                    continue;
                }

                $rowsByBggId[$bggId] = [
                    'nombre' => $game['name'],
                    'num_jugadores_min' => $game['min_players'] ?? null,
                    'num_jugadores_max' => $game['max_players'] ?? null,
                    'categoria_id' => $categoria->id,
                    'estado' => 'disponible',
                    'bgg_id' => $bggId,
                    'created_at' => $now,
                    'updated_at' => $now,
                ];

                $imageUrl = $this->normalizeImageUrl($game['image'] ?? $game['thumbnail'] ?? null);
                if ($imageUrl) {
                    $imagesPending[] = [
                        'bgg_id' => $bggId,
                        'image_url' => $imageUrl,
                    ];
                }
            }

            $rowsToInsert = array_values($rowsByBggId);
            $imported = count($rowsToInsert);
            $skipped = count($existingBggIds);

            if ($imported > 0) {
                foreach (array_chunk($rowsToInsert, 100) as $chunk) {
                    Juego::insert($chunk);
                }
                $this->attachCategoriaBulk($categoria->id, array_keys($rowsByBggId));
            }

            if ($propietario) {
                $this->attachPropietarioBulk($propietario->id, $bggIds);
            }

            return response()->json([
                'imported' => $imported,
                'skipped' => $skipped,
                'images_pending' => $imagesPending,
            ]);
        } catch (\Throwable $e) {
            Log::error('BGG import failed', [
                'error' => $e->getMessage(),
                'file' => $e->getFile(),
                'line' => $e->getLine(),
                'trace' => array_slice(explode("\n", $e->getTraceAsString()), 0, 5),
            ]);

            return response()->json([
                'message' => 'Error al importar: ' . $e->getMessage(),
                'exception' => class_basename($e),
            ], 500);
        }
    }

    public function importExpansions(Request $request): JsonResponse
    {
        $request->validate([
            'expansions' => 'required|array|min:1',
            'expansions.*.bgg_id' => 'required|integer',
            'expansions.*.name' => 'required|string',
            'bgg_username' => 'nullable|string',
        ]);

        try {
            $apiKey = config('services.bgg.api_key');
            $categoria = Categoria::firstOrCreate(
                ['nombre' => 'Importado BGG'],
                ['descripcion' => 'Juegos importados desde BoardGameGeek']
            );

            $propietario = $this->resolveOwner($request->input('bgg_username'));

            $expansions = $request->input('expansions');
            $expansionBggIds = array_values(array_unique(array_map(fn ($e) => (int) $e['bgg_id'], $expansions)));

            $existingBggIds = Juego::whereIn('bgg_id', $expansionBggIds)->pluck('bgg_id')->all();
            $existingSet = array_flip($existingBggIds);

            $toResolve = array_values(array_filter($expansionBggIds, fn ($id) => !isset($existingSet[$id])));
            $baseIdMap = $this->findBaseGamesBggIds($toResolve, $apiKey);

            $baseBggIds = array_values(array_unique(array_filter($baseIdMap)));
            $baseGames = Juego::whereIn('bgg_id', $baseBggIds)->pluck('id', 'bgg_id')->all();

            $now = now();
            $rowsByBggId = [];
            $imagesPending = [];
            $omitted = [];
            $attachBggIds = [];

            foreach ($expansions as $expansion) {
                $bggId = (int) $expansion['bgg_id'];

                if (isset($existingSet[$bggId])) {
                    $attachBggIds[] = $bggId;
                    continue;
                }

                if (isset($rowsByBggId[$bggId])) {
                    continue;
                }

                $baseBggId = $baseIdMap[$bggId] ?? null;
                if (!$baseBggId) {
                    $omitted[] = $expansion['name'];
                    continue;
                }

                $baseLocalId = $baseGames[$baseBggId] ?? null;
                if (!$baseLocalId) {
                    $omitted[] = $expansion['name'] . ' (juego base BGG #' . $baseBggId . ' no encontrado)';
                    continue;
                }

                $rowsByBggId[$bggId] = [
                    'nombre' => $expansion['name'],
                    'bgg_id' => $bggId,
                    'num_jugadores_min' => $expansion['min_players'] ?? null,
                    'num_jugadores_max' => $expansion['max_players'] ?? null,
                    'categoria_id' => $categoria->id,
                    'estado' => 'disponible',
                    'juego_base_id' => $baseLocalId,
                    'created_at' => $now,
                    'updated_at' => $now,
                ];
                $attachBggIds[] = $bggId;

                $imageUrl = $this->normalizeImageUrl($expansion['image'] ?? $expansion['thumbnail'] ?? null);
                if ($imageUrl) {
                    $imagesPending[] = [
                        'bgg_id' => $bggId,
                        'image_url' => $imageUrl,
                    ];
                }
            }

            $rowsToInsert = array_values($rowsByBggId);
            $imported = count($rowsToInsert);
            $skipped = count($existingBggIds);

            if ($imported > 0) {
                foreach (array_chunk($rowsToInsert, 100) as $chunk) {
                    Juego::insert($chunk);
                }
                $this->attachCategoriaBulk($categoria->id, array_keys($rowsByBggId));
            }

            if ($propietario && !empty($attachBggIds)) {
                $this->attachPropietarioBulk($propietario->id, $attachBggIds);
            }

            return response()->json([
                'imported' => $imported,
                'skipped' => $skipped,
                'omitted' => $omitted,
                'omitted_count' => count($omitted),
                'images_pending' => $imagesPending,
            ]);
        } catch (\Throwable $e) {
            Log::error('BGG import expansions failed', [
                'error' => $e->getMessage(),
                'file' => $e->getFile(),
                'line' => $e->getLine(),
                'trace' => array_slice(explode("\n", $e->getTraceAsString()), 0, 5),
            ]);

            return response()->json([
                'message' => 'Error al importar expansiones: ' . $e->getMessage(),
                'exception' => class_basename($e),
            ], 500);
        }
    }

    public function importImages(Request $request): JsonResponse
    {
        $request->validate([
            'images' => 'required|array|min:1|max:30',
            'images.*.bgg_id' => 'required|integer',
            'images.*.image_url' => 'required|string',
        ]);

        $items = $request->input('images');
        $succeeded = 0;
        $failed = 0;
        $failures = [];

        $responses = Http::pool(function (Pool $pool) use ($items) {
            return array_map(
                fn ($item) => $pool
                    ->as('bgg_' . $item['bgg_id'])
                    ->timeout(self::IMAGE_TIMEOUT)
                    ->withHeaders([
                        'User-Agent' => self::IMAGE_USER_AGENT,
                        'Accept' => 'image/*',
                    ])
                    ->get($item['image_url']),
                $items
            );
        });

        foreach ($items as $item) {
            $key = 'bgg_' . $item['bgg_id'];
            $response = $responses[$key] ?? null;

            if ($response instanceof \Throwable) {
                Log::warning('BGG image download threw', [
                    'bgg_id' => $item['bgg_id'],
                    'url' => $item['image_url'],
                    'error' => $response->getMessage(),
                ]);
                $failed++;
                $failures[] = $item['bgg_id'];
                continue;
            }

            if (!$response || !$response->successful()) {
                Log::warning('BGG image download failed', [
                    'bgg_id' => $item['bgg_id'],
                    'url' => $item['image_url'],
                    'status' => $response?->status(),
                ]);
                $failed++;
                $failures[] = $item['bgg_id'];
                continue;
            }

            $extension = pathinfo(parse_url($item['image_url'], PHP_URL_PATH), PATHINFO_EXTENSION) ?: 'jpg';

            try {
                $publicPath = $this->storeImage($item['bgg_id'], $extension, $response->body());

                $juego = Juego::where('bgg_id', $item['bgg_id'])->first();
                if ($juego) {
                    $juego->update(['imagen' => $publicPath]);
                }
                $succeeded++;
            } catch (\Throwable $e) {
                Log::error('BGG image store failed', [
                    'bgg_id' => $item['bgg_id'],
                    'error' => $e->getMessage(),
                ]);
                $failed++;
                $failures[] = $item['bgg_id'];
            }
        }

        return response()->json([
            'processed' => count($items),
            'succeeded' => $succeeded,
            'failed' => $failed,
            'failures' => $failures,
        ]);
    }

    /**
     * Guarda una imagen de juego y devuelve la ruta pública (o URL absoluta si es R2/S3).
     *
     * - Si hay R2 configurado (R2_BUCKET presente), sube a R2 con prefijo por tenant
     *   y devuelve URL pública completa.
     * - Si no, cae al disco público local y devuelve la ruta relativa /storage/...
     */
    private function storeImage(int $bggId, string $extension, string $body): string
    {
        $r2Configured = filled(config('filesystems.disks.r2.bucket'))
            && filled(config('filesystems.disks.r2.endpoint'));

        if ($r2Configured) {
            $tenantId = function_exists('tenant') ? (tenant()?->id ?? 'central') : 'central';
            $key = "tenants/{$tenantId}/juegos/bgg_{$bggId}.{$extension}";

            Storage::disk('r2')->put($key, $body, 'public');

            $publicUrl = rtrim((string) config('filesystems.disks.r2.url'), '/');
            if ($publicUrl !== '') {
                return $publicUrl . '/' . $key;
            }
            return Storage::disk('r2')->url($key);
        }

        $filename = "juegos/bgg_{$bggId}.{$extension}";
        Storage::disk('public')->put($filename, $body);
        return "/storage/{$filename}";
    }

    private function attachPropietarioBulk(int $propietarioId, array $bggIds): void
    {
        if (empty($bggIds)) {
            return;
        }

        $juegoIds = Juego::whereIn('bgg_id', $bggIds)->pluck('id')->all();
        if (empty($juegoIds)) {
            return;
        }

        $now = now();
        $rows = array_map(fn ($juegoId) => [
            'juego_id' => $juegoId,
            'propietario_id' => $propietarioId,
            'created_at' => $now,
            'updated_at' => $now,
        ], $juegoIds);

        foreach (array_chunk($rows, 500) as $chunk) {
            DB::table('juego_propietario')->insertOrIgnore($chunk);
        }
    }

    private function attachCategoriaBulk(int $categoriaId, array $bggIds): void
    {
        if (empty($bggIds)) {
            return;
        }

        $juegoIds = Juego::whereIn('bgg_id', $bggIds)->pluck('id')->all();
        if (empty($juegoIds)) {
            return;
        }

        $now = now();
        $rows = array_map(fn ($juegoId) => [
            'juego_id' => $juegoId,
            'categoria_id' => $categoriaId,
            'created_at' => $now,
            'updated_at' => $now,
        ], $juegoIds);

        foreach (array_chunk($rows, 500) as $chunk) {
            DB::table('juego_categoria')->insertOrIgnore($chunk);
        }
    }

    private function resolveOwner(?string $bggUsername): ?Propietario
    {
        if (!$bggUsername) {
            return null;
        }

        return Propietario::whereRaw('LOWER(bgg_username) = ?', [strtolower($bggUsername)])->first();
    }

    private function findBaseGamesBggIds(array $expansionBggIds, ?string $apiKey): array
    {
        if (empty($expansionBggIds)) {
            return [];
        }

        $headers = [
            'Accept' => 'application/xml',
            'User-Agent' => self::IMAGE_USER_AGENT,
        ];

        if ($apiKey) {
            $headers['Authorization'] = 'Bearer ' . $apiKey;
        }

        $map = [];

        foreach (array_chunk($expansionBggIds, 50) as $chunk) {
            $response = Http::timeout(30)->withHeaders($headers)
                ->get(self::BGG_API_URL . '/thing', [
                    'id' => implode(',', $chunk),
                    'type' => 'boardgameexpansion',
                ]);

            if ($response->failed()) {
                Log::warning('BGG bulk thing request failed', [
                    'ids_count' => count($chunk),
                    'status' => $response->status(),
                ]);
                continue;
            }

            $data = @simplexml_load_string($response->body());
            if ($data === false || !isset($data->item)) {
                continue;
            }

            foreach ($data->item as $item) {
                $expansionId = (int) ($item['id'] ?? 0);
                if (!$expansionId) {
                    continue;
                }

                foreach ($item->link as $link) {
                    if ((string) $link['type'] === 'boardgameexpansion' && (string) $link['inbound'] === 'true') {
                        $map[$expansionId] = (int) $link['id'];
                        break;
                    }
                }
            }
        }

        return $map;
    }

    public function search(Request $request): JsonResponse
    {
        $query = trim((string) $request->input('query', ''));

        if ($query === '') {
            return response()->json(['query' => '', 'games' => []]);
        }

        // Si parece un código de barras (solo dígitos, 8-14 caracteres), BGG no
        // lo soporta de forma nativa: devolvemos vacío para que el cliente
        // pueda ofrecer búsqueda manual.
        if (preg_match('/^\d{8,14}$/', $query)) {
            return response()->json([
                'query' => $query,
                'games' => [],
                'reason' => 'barcode_unsupported',
            ]);
        }

        // Limitamos la longitud: OCR puede devolver texto muy ruidoso.
        if (mb_strlen($query) > 120) {
            $query = mb_substr($query, 0, 120);
        }

        $apiKey = config('services.bgg.api_key');
        $headers = [
            'Accept' => 'application/xml',
            'User-Agent' => self::IMAGE_USER_AGENT,
        ];
        if ($apiKey) {
            $headers['Authorization'] = 'Bearer ' . $apiKey;
        }

        try {
            $response = Http::timeout(30)->withHeaders($headers)
                ->get(self::BGG_API_URL . '/search', [
                    'query' => $query,
                    'type' => 'boardgame,boardgameexpansion',
                ]);
        } catch (\Throwable $e) {
            Log::warning('BGG search request failed', [
                'query' => $query,
                'error' => $e->getMessage(),
            ]);
            return response()->json([
                'message' => 'No se pudo contactar con BGG.',
                'games' => [],
            ], 502);
        }

        if ($response->failed()) {
            return response()->json([
                'message' => 'Error al buscar en BGG.',
                'games' => [],
            ], $response->status());
        }

        $games = $this->parseSearchXml($response->body());

        if (!empty($games)) {
            $topIds = array_slice(array_map(fn ($g) => $g['bgg_id'], $games), 0, 10);
            $details = $this->fetchThingDetails($topIds, $apiKey);
            foreach ($games as &$game) {
                if (isset($details[$game['bgg_id']])) {
                    $game = array_merge($game, $details[$game['bgg_id']]);
                }
            }
            unset($game);
        }

        return response()->json([
            'query' => $query,
            'total' => count($games),
            'games' => $games,
        ]);
    }

    public function plays(string $username): JsonResponse
    {
        $apiKey = config('services.bgg.api_key');
        if (empty($apiKey)) {
            return response()->json([
                'message' => 'BGG_API_KEY no configurada.',
            ], 500);
        }

        $page = request()->input('page', 1);

        $response = Http::timeout(30)->withHeaders([
            'Accept' => 'application/xml',
            'Authorization' => 'Bearer ' . $apiKey,
            'User-Agent' => self::IMAGE_USER_AGENT,
        ])->get(self::BGG_API_URL . '/plays', [
            'username' => $username,
            'page' => $page,
        ]);

        if ($response->failed()) {
            return response()->json([
                'message' => 'Error al obtener partidas de BGG.',
            ], $response->status());
        }

        return response()->json($this->parsePlaysXml($response->body(), $username));
    }

    private function fetchWithRetry(string $url, array $params, string $apiKey)
    {
        $response = null;

        for ($attempt = 0; $attempt < self::MAX_RETRIES; $attempt++) {
            $response = Http::timeout(30)->withHeaders([
                'Accept' => 'application/xml',
                'Authorization' => 'Bearer ' . $apiKey,
                'User-Agent' => self::IMAGE_USER_AGENT,
            ])->get($url, $params);

            if ($response->status() !== 202) {
                return $response;
            }

            sleep(self::RETRY_DELAY_SECONDS);
        }

        return null;
    }

    private function normalizeImageUrl(?string $url): ?string
    {
        if (!$url) {
            return null;
        }

        $url = trim($url);
        if ($url === '') {
            return null;
        }

        if (str_starts_with($url, '//')) {
            return 'https:' . $url;
        }

        if (!preg_match('#^https?://#i', $url)) {
            return null;
        }

        return $url;
    }

    private function parsePlaysXml(string $xml, string $username): array
    {
        $data = @simplexml_load_string($xml);

        if ($data === false) {
            return ['username' => $username, 'total' => 0, 'plays' => []];
        }

        $total = (int) ($data['total'] ?? 0);
        $plays = [];

        if (isset($data->play)) {
            foreach ($data->play as $play) {
                $item = $play->item ?? null;
                $players = [];

                if (isset($play->players->player)) {
                    foreach ($play->players->player as $player) {
                        $players[] = [
                            'name' => (string) $player['name'],
                            'score' => (string) ($player['score'] ?? ''),
                            'win' => (string) ($player['win'] ?? '0') === '1',
                            'new' => (string) ($player['new'] ?? '0') === '1',
                        ];
                    }
                }

                $plays[] = [
                    'id' => (int) $play['id'],
                    'date' => (string) $play['date'],
                    'quantity' => (int) ($play['quantity'] ?? 1),
                    'game_name' => (string) ($item['name'] ?? ''),
                    'game_bgg_id' => (int) ($item['objectid'] ?? 0),
                    'comments' => (string) ($play->comments ?? ''),
                    'players' => $players,
                ];
            }
        }

        return [
            'username' => $username,
            'total' => $total,
            'plays' => $plays,
        ];
    }

    private function parseSearchXml(string $xml): array
    {
        $data = @simplexml_load_string($xml);

        if ($data === false || !isset($data->item)) {
            return [];
        }

        $games = [];
        $seen = [];

        foreach ($data->item as $item) {
            $bggId = (int) ($item['id'] ?? 0);
            if (!$bggId || isset($seen[$bggId])) {
                continue;
            }
            $seen[$bggId] = true;

            $name = (string) ($item->name['value'] ?? '');
            if ($name === '') {
                continue;
            }

            $games[] = [
                'bgg_id' => $bggId,
                'name' => $name,
                'year' => (int) ($item->yearpublished['value'] ?? 0),
                'type' => (string) ($item['type'] ?? 'boardgame'),
            ];
        }

        return $games;
    }

    private function fetchThingDetails(array $bggIds, ?string $apiKey): array
    {
        if (empty($bggIds)) {
            return [];
        }

        $headers = [
            'Accept' => 'application/xml',
            'User-Agent' => self::IMAGE_USER_AGENT,
        ];
        if ($apiKey) {
            $headers['Authorization'] = 'Bearer ' . $apiKey;
        }

        try {
            $response = Http::timeout(30)->withHeaders($headers)
                ->get(self::BGG_API_URL . '/thing', [
                    'id' => implode(',', $bggIds),
                ]);
        } catch (\Throwable $e) {
            Log::warning('BGG thing lookup failed', [
                'ids' => $bggIds,
                'error' => $e->getMessage(),
            ]);
            return [];
        }

        if ($response->failed()) {
            return [];
        }

        $data = @simplexml_load_string($response->body());
        if ($data === false || !isset($data->item)) {
            return [];
        }

        $details = [];
        foreach ($data->item as $item) {
            $bggId = (int) ($item['id'] ?? 0);
            if (!$bggId) {
                continue;
            }

            $primaryName = '';
            if (isset($item->name)) {
                foreach ($item->name as $nameNode) {
                    if ((string) $nameNode['type'] === 'primary') {
                        $primaryName = (string) $nameNode['value'];
                        break;
                    }
                }
            }

            $details[$bggId] = [
                'name' => $primaryName !== '' ? $primaryName : null,
                'year' => (int) ($item->yearpublished['value'] ?? 0),
                'image' => (string) ($item->image ?? ''),
                'thumbnail' => (string) ($item->thumbnail ?? ''),
                'min_players' => (int) ($item->minplayers['value'] ?? 0),
                'max_players' => (int) ($item->maxplayers['value'] ?? 0),
                'playing_time' => (int) ($item->playingtime['value'] ?? 0),
                'description' => trim((string) ($item->description ?? '')),
            ];

            // Evitamos sobrescribir con null si no tenemos nombre primario.
            $details[$bggId] = array_filter(
                $details[$bggId],
                fn ($v) => $v !== null && $v !== '' && $v !== 0
            );
        }

        return $details;
    }

    private function parseCollectionXml(string $xml): array
    {
        $data = @simplexml_load_string($xml);

        if ($data === false || !isset($data->item)) {
            return [];
        }

        $games = [];

        foreach ($data->item as $item) {
            $stats = $item->stats ?? null;
            $rating = $stats?->rating ?? null;

            $games[] = [
                'bgg_id' => (int) $item['objectid'],
                'name' => (string) $item->name,
                'year' => (int) ($item->yearpublished ?? 0),
                'image' => (string) ($item->image ?? ''),
                'thumbnail' => (string) ($item->thumbnail ?? ''),
                'min_players' => (int) ($stats['minplayers'] ?? 0),
                'max_players' => (int) ($stats['maxplayers'] ?? 0),
                'playing_time' => (int) ($stats['playingtime'] ?? 0),
                'rating' => round((float) ($rating->average['value'] ?? 0), 1),
                'user_rating' => (string) ($rating['value'] ?? 'N/A'),
                'num_plays' => (int) ($item->numplays ?? 0),
            ];
        }

        usort($games, fn ($a, $b) => $b['rating'] <=> $a['rating']);

        return $games;
    }
}
