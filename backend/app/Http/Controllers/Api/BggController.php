<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Categoria;
use App\Models\Juego;
use App\Models\Propietario;
use App\Models\User;
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
    private const BGG_LOGIN_URL = 'https://boardgamegeek.com/login/api/v1';
    private const MAX_RETRIES = 5;
    private const RETRY_DELAY_SECONDS = 2;
    private const IMAGE_USER_AGENT = 'Ludoteca/1.0 (BoardGameGeek Integration)';
    private const IMAGE_TIMEOUT = 20;

    public function connect(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'username' => 'required|string|max:255',
            'password' => 'required|string',
        ]);

        $username = trim($validated['username']);
        $password = $validated['password'];

        try {
            $cookieJar = new \GuzzleHttp\Cookie\CookieJar();
            $browserHeaders = [
                'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
                'Accept' => 'application/json, text/plain, */*',
                'Accept-Language' => 'en-US,en;q=0.9,es;q=0.8',
                'Origin' => 'https://boardgamegeek.com',
                'Referer' => 'https://boardgamegeek.com/login',
            ];

            // Visita previa para obtener cookies base (Cloudflare/sesión).
            Http::withOptions(['cookies' => $cookieJar])
                ->withHeaders(array_merge($browserHeaders, [
                    'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                ]))
                ->get('https://boardgamegeek.com/');

            $response = Http::withOptions(['cookies' => $cookieJar])
                ->withHeaders(array_merge($browserHeaders, [
                    'Content-Type' => 'application/json',
                ]))->post(self::BGG_LOGIN_URL, [
                    'credentials' => [
                        'username' => $username,
                        'password' => $password,
                    ],
                ]);
        } catch (\Throwable $e) {
            Log::warning('BGG connect login request failed', [
                'error' => $e->getMessage(),
            ]);

            return response()->json([
                'message' => 'No se pudo contactar con BoardGameGeek.',
            ], 502);
        }

        if ($response->status() >= 400) {
            return response()->json([
                'message' => 'Usuario o contraseña de BGG incorrectos.',
            ], 422);
        }

        $session = $this->extractAuthCookiesFromLogin($response, $cookieJar);

        Log::info('BGG connect cookie names', [
            'status' => $response->status(),
            'names' => $this->cookieNames($session ?? ''),
        ]);

        if ($session === null) {
            Log::warning('BGG connect succeeded without session cookies', [
                'status' => $response->status(),
            ]);

            return response()->json([
                'message' => 'BGG no devolvió una sesión válida. Inténtalo de nuevo.',
            ], 502);
        }

        /** @var User $user */
        $user = $request->user();
        $user->bgg_username = $username;
        $user->bgg_session = $session;
        $user->bgg_connected_at = now();
        $user->save();

        Propietario::where('es_principal', true)->update([
            'bgg_username' => $username,
        ]);

        return response()->json([
            'message' => 'Conectado a BoardGameGeek.',
            'user' => $user->toApiArray(),
        ]);
    }

    public function disconnect(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        $user->bgg_session = null;
        $user->bgg_connected_at = null;
        $user->save();

        return response()->json([
            'message' => 'Desconectado de BoardGameGeek.',
            'user' => $user->toApiArray(),
        ]);
    }

    public function writeContext(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        if (!$user->isBggConnected()) {
            return response()->json([
                'message' => 'Conecta tu cuenta de BGG en el perfil primero.',
            ], 422);
        }

        $cookie = $this->authCookieHeader((string) $user->bgg_session);
        if ($cookie === '') {
            return response()->json([
                'message' => 'La sesión de BGG no tiene cookies válidas. Vuelve a conectar la cuenta en el perfil.',
            ], 422);
        }

        $username = trim((string) $user->bgg_username);

        return response()->json([
            'username' => $username,
            'cookie' => $cookie,
            'user_agent' => 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36',
            'origin' => 'https://boardgamegeek.com',
            'referer' => 'https://boardgamegeek.com/collection/user/'.$username,
        ]);
    }

    public function writeDebug(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        Log::warning('BGG client write debug', [
            'user_id' => $user->id,
            'bgg_username' => $user->bgg_username,
            'status' => $request->input('status'),
            'url' => $request->input('url'),
            'redirected' => $request->boolean('redirected'),
            'type' => $request->input('type'),
            'headers' => $request->input('headers'),
            'body' => substr((string) $request->input('body', ''), 0, 8000),
            'via' => $request->input('via'),
            'diagnosis' => $request->input('diagnosis'),
            'attempt' => $request->input('attempt'),
            'phase' => $request->input('phase'),
            'message' => $request->input('message'),
        ]);

        return response()->json(['ok' => true]);
    }

    public function ownedIds(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        if (!$user->isBggConnected()) {
            return response()->json([
                'message' => 'Conecta tu cuenta de BGG en el perfil primero.',
            ], 422);
        }

        $result = $this->fetchOwnedBggIds($user);
        if ($result['error'] !== null) {
            return response()->json([
                'message' => $result['error'],
            ], $result['status'] ?? 502);
        }

        return response()->json([
            'username' => $user->bgg_username,
            'ids' => array_values($result['ids']),
            'total' => count($result['ids']),
        ]);
    }

    public function exportPreview(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        if (!$user->isBggConnected()) {
            return response()->json([
                'message' => 'Conecta tu cuenta de BGG en el perfil primero.',
            ], 422);
        }

        $propietario = $this->resolveExportPropietario($user);
        if (!$propietario) {
            return response()->json([
                'message' => 'No hay un propietario vinculado al usuario BGG «'.$user->bgg_username.'».',
            ], 422);
        }

        $collection = $this->fetchCollectionStatusSets($user);
        if ($collection['error'] !== null) {
            return response()->json([
                'message' => $collection['error'],
            ], $collection['status'] ?? 502);
        }

        $ownedSet = array_fill_keys($collection['owned'], true);
        $prevOwnedSet = array_fill_keys($collection['prevowned'], true);
        $ownedNames = $collection['owned_names'] ?? [];
        $prevOwnedNames = $collection['prevowned_names'] ?? [];
        foreach ($request->input('known_owned_ids', []) as $id) {
            $id = (int) $id;
            if ($id > 0) {
                $ownedSet[$id] = true;
            }
        }
        foreach ($request->input('known_prevowned_ids', []) as $id) {
            $id = (int) $id;
            if ($id > 0) {
                $prevOwnedSet[$id] = true;
            }
        }
        foreach ($request->input('known_owned_names', []) as $name) {
            $key = $this->normalizeGameName((string) $name);
            if ($key !== '') {
                $ownedNames[$key] = true;
            }
        }
        foreach ($request->input('known_prevowned_names', []) as $name) {
            $key = $this->normalizeGameName((string) $name);
            if ($key !== '') {
                $prevOwnedNames[$key] = true;
            }
        }
        $juegos = Juego::query()
            ->whereHas('propietarios', function ($q) use ($propietario) {
                $q->where('propietarios.id', $propietario->id);
            })
            ->orderBy('nombre')
            ->get(['id', 'nombre', 'bgg_id', 'es_expansion', 'juego_base_id', 'estado']);

        $toUpload = [];
        $toPrevOwned = [];
        $already = [];
        $omitted = [];
        $byNameCount = 0;

        foreach ($juegos as $juego) {
            $bggId = $juego->bgg_id ? (int) $juego->bgg_id : 0;
            $nameKey = $this->normalizeGameName((string) $juego->nombre);
            $payload = [
                'id' => $juego->id,
                'nombre' => $juego->nombre,
                'bgg_id' => $juego->bgg_id,
                'es_expansion' => (bool) ($juego->es_expansion || $juego->juego_base_id),
                'match_by_name' => $bggId <= 0,
                'action' => 'own',
            ];

            if (($juego->estado ?? '') === 'vendido') {
                $payload['action'] = 'prevowned';
                if ($this->isListedInBgg($bggId, $nameKey, $prevOwnedSet, $prevOwnedNames)) {
                    $already[] = $payload;
                    continue;
                }
                if ($bggId <= 0) {
                    $byNameCount++;
                }
                $toPrevOwned[] = $payload;
                continue;
            }

            if ($this->isListedInBgg($bggId, $nameKey, $ownedSet, $ownedNames)) {
                $already[] = $payload;
                continue;
            }

            if ($bggId <= 0) {
                $byNameCount++;
            }

            $toUpload[] = $payload;
        }

        return response()->json([
            'username' => $user->bgg_username,
            'propietario' => [
                'id' => $propietario->id,
                'nombre' => $propietario->nombre,
                'bgg_username' => $propietario->bgg_username,
            ],
            'to_upload' => $toUpload,
            'to_prev_owned' => $toPrevOwned,
            'already_in_bgg' => $already,
            'omitted' => $omitted,
            'counts' => [
                'to_upload' => count($toUpload),
                'to_prev_owned' => count($toPrevOwned),
                'already_in_bgg' => count($already),
                'omitted' => count($omitted),
                'match_by_name' => $byNameCount,
                'total_changes' => count($toUpload) + count($toPrevOwned),
                'coleccion_local' => $juegos->count(),
            ],
        ]);
    }

    public function exportItem(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        if (!$user->isBggConnected()) {
            return response()->json([
                'message' => 'Conecta tu cuenta de BGG en el perfil primero.',
                'success' => false,
            ], 422);
        }

        $validated = $request->validate([
            'juego_id' => 'required|integer',
            'client_write' => 'sometimes|boolean',
        ]);
        $clientWrite = $request->boolean('client_write');

        $propietario = $this->resolveExportPropietario($user);
        if (!$propietario) {
            return response()->json([
                'success' => false,
                'message' => 'No hay un propietario vinculado al usuario BGG «'.$user->bgg_username.'».',
            ], 422);
        }

        $juego = Juego::query()
            ->whereKey($validated['juego_id'])
            ->whereHas('propietarios', function ($q) use ($propietario) {
                $q->where('propietarios.id', $propietario->id);
            })
            ->first();

        if (!$juego) {
            return response()->json([
                'success' => false,
                'message' => 'Juego no encontrado en la colección del propietario BGG conectado.',
            ], 404);
        }

        $markPrevOwned = ($juego->estado ?? '') === 'vendido';

        $resolvedByName = false;
        $matchedName = null;
        $bggId = $juego->bgg_id ? (int) $juego->bgg_id : null;

        if (!$bggId) {
            $resolved = $this->resolveBggIdByName($juego);
            if (isset($resolved['error'])) {
                return response()->json([
                    'success' => false,
                    'juego_id' => $juego->id,
                    'nombre' => $juego->nombre,
                    'message' => $resolved['error'],
                ], 422);
            }

            $bggId = (int) $resolved['bgg_id'];
            $resolvedByName = true;
            $matchedName = $resolved['matched_name'] ?? null;

            $duplicate = Juego::where('bgg_id', $bggId)
                ->where('id', '!=', $juego->id)
                ->first();
            if ($duplicate) {
                return response()->json([
                    'success' => false,
                    'juego_id' => $juego->id,
                    'nombre' => $juego->nombre,
                    'bgg_id' => $bggId,
                    'message' => 'El ID BGG #'.$bggId.' ya está vinculado a «'.$duplicate->nombre.'»',
                ], 422);
            }

            $juego->bgg_id = $bggId;
            $juego->save();
        }

        if ($markPrevOwned) {
            if ($this->isBggIdPrevOwnedByUser((string) $user->bgg_username, $bggId)) {
                return response()->json([
                    'success' => true,
                    'skipped' => true,
                    'needs_write' => false,
                    'juego_id' => $juego->id,
                    'nombre' => $juego->nombre,
                    'bgg_id' => $bggId,
                    'bgg_id_saved' => $resolvedByName,
                    'matched_name' => $matchedName,
                    'action' => 'prevowned',
                    'message' => 'Ya estaba como Previously Owned en BGG',
                ]);
            }

            if ($clientWrite) {
                return response()->json([
                    'success' => true,
                    'skipped' => false,
                    'needs_write' => true,
                    'juego_id' => $juego->id,
                    'nombre' => $juego->nombre,
                    'bgg_id' => $bggId,
                    'bgg_id_saved' => $resolvedByName,
                    'matched_name' => $matchedName,
                    'action' => 'prevowned',
                    'message' => 'Listo para marcar Previously Owned desde el dispositivo',
                ]);
            }

            $result = $this->markGameAsPreviouslyOwnedOnBgg($user, $bggId);
            if (!$result['success']) {
                // Nunca invalidar bgg_session aquí: un 403/WAF/rate-limit
                // de BGG no implica sesión caducada y desconectaba al usuario.
                return response()->json([
                    'success' => false,
                    'juego_id' => $juego->id,
                    'nombre' => $juego->nombre,
                    'bgg_id' => $bggId,
                    'bgg_id_saved' => $resolvedByName,
                    'matched_name' => $matchedName,
                    'action' => 'prevowned',
                    'message' => $result['message'] ?? 'No se pudo marcar como Previously Owned',
                    'session_expired' => false,
                    'rate_limited' => (bool) ($result['rate_limited'] ?? false),
                ], 502);
            }

            return response()->json([
                'success' => true,
                'skipped' => false,
                'juego_id' => $juego->id,
                'nombre' => $juego->nombre,
                'bgg_id' => $bggId,
                'bgg_id_saved' => $resolvedByName,
                'matched_name' => $matchedName,
                'action' => 'prevowned',
                'message' => 'Marcado como Previously Owned en BGG',
            ]);
        }

        if ($resolvedByName && $this->isBggIdOwnedByUser($user->bgg_username, $bggId)) {
            return response()->json([
                'success' => true,
                'skipped' => true,
                'needs_write' => false,
                'juego_id' => $juego->id,
                'nombre' => $juego->nombre,
                'bgg_id' => $bggId,
                'bgg_id_saved' => true,
                'matched_name' => $matchedName,
                'action' => 'own',
                'message' => 'Encontrado por nombre; ya estaba en tu colección BGG',
            ]);
        }

        if ($clientWrite) {
            return response()->json([
                'success' => true,
                'skipped' => false,
                'needs_write' => true,
                'juego_id' => $juego->id,
                'nombre' => $juego->nombre,
                'bgg_id' => $bggId,
                'bgg_id_saved' => $resolvedByName,
                'matched_name' => $matchedName,
                'action' => 'own',
                'message' => 'Listo para añadir a BGG desde el dispositivo',
            ]);
        }

        $result = $this->addGameToBggCollection($user, $bggId);

        if (!$result['success']) {
            // Nunca invalidar bgg_session aquí: fallos ambiguos de BGG
            // (WAF/rate-limit) no deben desconectar la cuenta.
            return response()->json([
                'success' => false,
                'juego_id' => $juego->id,
                'nombre' => $juego->nombre,
                'bgg_id' => $bggId,
                'bgg_id_saved' => $resolvedByName,
                'matched_name' => $matchedName,
                'action' => 'own',
                'message' => $result['message'] ?? 'No se pudo añadir a BGG',
                'session_expired' => false,
                'rate_limited' => (bool) ($result['rate_limited'] ?? false),
            ], 502);
        }

        return response()->json([
            'success' => true,
            'skipped' => false,
            'juego_id' => $juego->id,
            'nombre' => $juego->nombre,
            'bgg_id' => $bggId,
            'bgg_id_saved' => $resolvedByName,
            'matched_name' => $matchedName,
            'action' => 'own',
            'message' => $resolvedByName
                ? 'Encontrado por nombre y añadido a BGG'
                : 'Añadido a la colección de BGG',
        ]);
    }

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
            'showprivate' => 1,
        ], $apiKey, $this->collectionAuthCookie($username));

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
            'showprivate' => 1,
        ], $apiKey, $this->collectionAuthCookie($username));

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

    private function cookieJarToHeader(\GuzzleHttp\Cookie\CookieJar $cookieJar): ?string
    {
        $byName = [];
        foreach ($cookieJar as $cookie) {
            $name = $cookie->getName();
            $value = (string) $cookie->getValue();
            if (!$this->isBggAuthCookieName($name) || $this->isDiscardableCookieValue($value)) {
                continue;
            }
            if (method_exists($cookie, 'getExpires')) {
                $expires = $cookie->getExpires();
                if (is_numeric($expires) && (int) $expires > 0 && (int) $expires < time()) {
                    continue;
                }
            }
            $byName[$name] = $value;
        }

        return $this->joinAuthCookies($byName);
    }

    /**
     * BGG envía cada cookie dos veces (valor real + "deleted"). El CookieJar
     * se queda a veces con la borrada; leemos Set-Cookie a mano y ignoramos
     * las caducadas.
     */
    private function extractAuthCookiesFromLogin(
        \Illuminate\Http\Client\Response $response,
        \GuzzleHttp\Cookie\CookieJar $cookieJar,
    ): ?string {
        $byName = [];

        foreach ($cookieJar as $cookie) {
            $name = $cookie->getName();
            $value = (string) $cookie->getValue();
            if (!$this->isBggAuthCookieName($name) || $this->isDiscardableCookieValue($value)) {
                continue;
            }
            if (method_exists($cookie, 'getExpires')) {
                $expires = $cookie->getExpires();
                if (is_numeric($expires) && (int) $expires > 0 && (int) $expires < time()) {
                    continue;
                }
            }
            $byName[$name] = $value;
        }

        $rawHeaders = $response->headers()['Set-Cookie'] ?? [];
        foreach ((array) $rawHeaders as $header) {
            if (!is_string($header) || $header === '') {
                continue;
            }
            $attrs = array_map('trim', explode(';', $header));
            $pair = array_shift($attrs) ?? '';
            if (!str_contains($pair, '=')) {
                continue;
            }
            [$name, $value] = explode('=', $pair, 2);
            $name = trim($name);
            $value = trim($value);
            if (!$this->isBggAuthCookieName($name) || $this->isDiscardableCookieValue($value)) {
                continue;
            }
            $expired = false;
            foreach ($attrs as $attr) {
                if (str_starts_with(strtolower($attr), 'max-age=0')) {
                    $expired = true;
                }
                if (str_starts_with(strtolower($attr), 'expires=') && str_contains($attr, '1970')) {
                    $expired = true;
                }
            }
            if ($expired) {
                continue;
            }
            $byName[$name] = $value;
        }

        return $this->joinAuthCookies($byName);
    }

    private function sessionCookieJar(User $user): \GuzzleHttp\Cookie\CookieJar
    {
        return \GuzzleHttp\Cookie\CookieJar::fromArray(
            $this->parseCookieMap((string) $user->bgg_session),
            'boardgamegeek.com',
        );
    }

    /**
     * Propietario local cuya colección se sincroniza con la cuenta BGG conectada.
     */
    private function resolveExportPropietario(User $user): ?Propietario
    {
        $username = trim((string) $user->bgg_username);
        if ($username === '') {
            return null;
        }

        $byUsername = Propietario::whereRaw('LOWER(bgg_username) = ?', [strtolower($username)])
            ->first();
        if ($byUsername) {
            return $byUsername;
        }

        // Fallback: el propietario principal (se sincroniza el username al conectar).
        return Propietario::where('es_principal', true)->first();
    }

    /**
     * Busca un juego en BGG por nombre (exacto y, si hace falta, aproximado).
     *
     * @return array{bgg_id: int, matched_name: string}|array{error: string}
     */
    private function resolveBggIdByName(Juego $juego): array
    {
        $name = trim((string) $juego->nombre);
        if ($name === '') {
            return ['error' => 'El juego no tiene nombre para buscar en BGG'];
        }

        $isExpansion = (bool) ($juego->es_expansion || $juego->juego_base_id);

        $exact = $this->searchBggByName($name, true);
        $match = $this->pickBestBggMatch($name, $exact, $isExpansion);
        if ($match !== null) {
            return $match;
        }

        $fuzzy = $this->searchBggByName($name, false);
        $match = $this->pickBestBggMatch($name, $fuzzy, $isExpansion);
        if ($match !== null) {
            return $match;
        }

        if ($exact === [] && $fuzzy === []) {
            return ['error' => 'No se encontró en BGG por nombre'];
        }

        return ['error' => 'Varias coincidencias en BGG; no se pudo decidir automáticamente'];
    }

    /**
     * @return list<array{bgg_id: int, name: string, year: int, type: string}>
     */
    private function searchBggByName(string $query, bool $exact): array
    {
        $apiKey = config('services.bgg.api_key');
        $headers = [
            'Accept' => 'application/xml',
            'User-Agent' => self::IMAGE_USER_AGENT,
        ];
        if ($apiKey) {
            $headers['Authorization'] = 'Bearer '.$apiKey;
        }

        $params = [
            'query' => mb_substr($query, 0, 120),
            'type' => 'boardgame,boardgameexpansion',
        ];
        if ($exact) {
            $params['exact'] = 1;
        }

        try {
            $response = Http::timeout(20)->withHeaders($headers)
                ->get(self::BGG_API_URL.'/search', $params);
        } catch (\Throwable $e) {
            Log::warning('BGG name search failed', [
                'query' => $query,
                'exact' => $exact,
                'error' => $e->getMessage(),
            ]);

            return [];
        }

        if ($response->failed()) {
            return [];
        }

        return array_slice($this->parseSearchXml($response->body()), 0, 20);
    }

    /**
     * @param  list<array{bgg_id: int, name: string, year: int, type: string}>  $candidates
     * @return array{bgg_id: int, matched_name: string}|null
     */
    private function pickBestBggMatch(string $nombre, array $candidates, bool $preferExpansion): ?array
    {
        if ($candidates === []) {
            return null;
        }

        $normalized = $this->normalizeGameName($nombre);
        $exact = array_values(array_filter(
            $candidates,
            fn ($c) => $this->normalizeGameName((string) $c['name']) === $normalized
        ));

        $pool = $exact !== [] ? $exact : $candidates;

        $preferredType = $preferExpansion ? 'boardgameexpansion' : 'boardgame';
        $typed = array_values(array_filter(
            $pool,
            fn ($c) => ($c['type'] ?? '') === $preferredType
        ));
        if ($typed !== []) {
            $pool = $typed;
        }

        if (count($pool) === 1) {
            return [
                'bgg_id' => (int) $pool[0]['bgg_id'],
                'matched_name' => (string) $pool[0]['name'],
            ];
        }

        // Si hay varios con el mismo nombre normalizado, cogemos el de año más reciente.
        if ($exact !== [] && count($pool) > 1) {
            usort($pool, fn ($a, $b) => ((int) ($b['year'] ?? 0)) <=> ((int) ($a['year'] ?? 0)));

            return [
                'bgg_id' => (int) $pool[0]['bgg_id'],
                'matched_name' => (string) $pool[0]['name'],
            ];
        }

        return null;
    }

    private function normalizeGameName(string $name): string
    {
        $name = mb_strtolower(trim($name));
        $name = strtr($name, [
            'á' => 'a', 'à' => 'a', 'ä' => 'a', 'â' => 'a',
            'é' => 'e', 'è' => 'e', 'ë' => 'e', 'ê' => 'e',
            'í' => 'i', 'ì' => 'i', 'ï' => 'i', 'î' => 'i',
            'ó' => 'o', 'ò' => 'o', 'ö' => 'o', 'ô' => 'o',
            'ú' => 'u', 'ù' => 'u', 'ü' => 'u', 'û' => 'u',
            'ñ' => 'n', 'ç' => 'c',
        ]);
        $name = preg_replace('/[^a-z0-9]+/u', '', $name) ?? $name;

        return $name;
    }

    /**
     * @param  array<int, bool>  $idSet
     * @param  array<string, bool>  $nameSet
     */
    private function isListedInBgg(int $bggId, string $nameKey, array $idSet, array $nameSet): bool
    {
        if ($bggId > 0 && isset($idSet[$bggId])) {
            return true;
        }

        return $nameKey !== '' && isset($nameSet[$nameKey]);
    }

    private function isBggIdOwnedByUser(string $username, int $bggId): bool
    {
        return $this->collectionContainsBggId($username, $bggId, ['own' => 1]);
    }

    private function isBggIdPrevOwnedByUser(string $username, int $bggId): bool
    {
        return $this->collectionContainsBggId($username, $bggId, ['prevowned' => 1]);
    }

    /**
     * @param  array<string, int|string>  $statusFilters
     */
    private function collectionContainsBggId(string $username, int $bggId, array $statusFilters): bool
    {
        $apiKey = config('services.bgg.api_key');
        if (empty($apiKey) || $bggId <= 0) {
            return false;
        }

        $response = $this->fetchWithRetry(self::BGG_API_URL.'/collection', array_merge([
            'username' => $username,
            'id' => $bggId,
        ], $statusFilters), $apiKey);

        if (!$response || $response->failed()) {
            return false;
        }

        $data = @simplexml_load_string($response->body());
        if ($data === false || !isset($data->item)) {
            return false;
        }

        foreach ($data->item as $item) {
            if ((int) $item['objectid'] === $bggId) {
                return true;
            }
        }

        return false;
    }

    /**
     * Una pasada de colección (bases + expansiones) y clasifica own / prevowned.
     * Evita 4 llamadas seguidas al XML API, que BGG responde con 403/429.
     *
     * @return array{
     *     owned: list<int>,
     *     prevowned: list<int>,
     *     owned_names: array<string, bool>,
     *     prevowned_names: array<string, bool>,
     *     error: ?string,
     *     status?: int
     * }
     */
    private function fetchCollectionStatusSets(User $user): array
    {
        $username = trim((string) $user->bgg_username);
        $apiKey = config('services.bgg.api_key');
        $empty = [
            'owned' => [],
            'prevowned' => [],
            'owned_names' => [],
            'prevowned_names' => [],
        ];
        if ($username === '') {
            return $empty + ['error' => 'No hay usuario BGG conectado.', 'status' => 422];
        }
        if (empty($apiKey)) {
            return $empty + ['error' => 'BGG_API_KEY no configurada.', 'status' => 500];
        }

        $cookie = $this->authCookieHeader((string) ($user->bgg_session ?? ''));
        $response = $this->fetchWithRetry(
            self::BGG_API_URL.'/collection',
            [
                'username' => $username,
                'stats' => 0,
                'showprivate' => 1,
            ],
            $apiKey,
            $cookie !== '' ? $cookie : null,
        );

        if (!$response) {
            return $empty + [
                'error' => 'BGG está procesando la colección, inténtalo de nuevo en unos segundos.',
                'status' => 202,
            ];
        }

        if ($response->failed()) {
            Log::warning('BGG collection status fetch failed', [
                'username' => $username,
                'status' => $response->status(),
                'body' => substr($response->body(), 0, 300),
            ]);

            return $empty + [
                'error' => 'Error al obtener la colección de BGG (HTTP '.$response->status().'). Espera un minuto y vuelve a intentarlo.',
                'status' => $response->status() >= 400 ? $response->status() : 502,
            ];
        }

        $parsed = $this->parseCollectionStatusXml($response->body());

        $expansions = $this->fetchWithRetry(
            self::BGG_API_URL.'/collection',
            [
                'username' => $username,
                'stats' => 0,
                'showprivate' => 1,
                'subtype' => 'boardgameexpansion',
            ],
            $apiKey,
            $cookie !== '' ? $cookie : null,
        );
        if ($expansions && $expansions->successful()) {
            $extra = $this->parseCollectionStatusXml($expansions->body());
            $parsed['owned'] = array_values(array_unique(array_merge($parsed['owned'], $extra['owned'])));
            $parsed['prevowned'] = array_values(array_unique(array_merge($parsed['prevowned'], $extra['prevowned'])));
            $parsed['owned_names'] = $parsed['owned_names'] + $extra['owned_names'];
            $parsed['prevowned_names'] = $parsed['prevowned_names'] + $extra['prevowned_names'];
        }

        return $parsed + ['error' => null];
    }

    /**
     * @return array{
     *     owned: list<int>,
     *     prevowned: list<int>,
     *     owned_names: array<string, bool>,
     *     prevowned_names: array<string, bool>
     * }
     */
    private function parseCollectionStatusXml(string $xml): array
    {
        $owned = [];
        $prevOwned = [];
        $ownedNames = [];
        $prevOwnedNames = [];

        $data = @simplexml_load_string($xml);
        if ($data === false || !isset($data->item)) {
            return [
                'owned' => [],
                'prevowned' => [],
                'owned_names' => [],
                'prevowned_names' => [],
            ];
        }

        foreach ($data->item as $item) {
            $bggId = (int) $item['objectid'];
            $nameKey = $this->normalizeGameName((string) ($item->name ?? ''));
            $status = $item->status ?? null;
            if ($status === null) {
                continue;
            }

            $ids = [];
            if ($bggId > 0) {
                $ids[] = $bggId;
            }
            if (isset($item->version->item)) {
                foreach ($item->version->item as $version) {
                    $versionId = (int) ($version['id'] ?? 0);
                    if ($versionId > 0) {
                        $ids[] = $versionId;
                    }
                    $versionName = $this->normalizeGameName((string) ($version->name['value'] ?? $version->name ?? ''));
                    if ($versionName !== '') {
                        if ((string) ($status['own'] ?? '0') === '1') {
                            $ownedNames[$versionName] = true;
                        }
                        if ((string) ($status['prevowned'] ?? '0') === '1') {
                            $prevOwnedNames[$versionName] = true;
                        }
                    }
                }
            }

            if ((string) ($status['own'] ?? '0') === '1') {
                foreach ($ids as $id) {
                    $owned[$id] = $id;
                }
                if ($nameKey !== '') {
                    $ownedNames[$nameKey] = true;
                }
            }
            if ((string) ($status['prevowned'] ?? '0') === '1') {
                foreach ($ids as $id) {
                    $prevOwned[$id] = $id;
                }
                if ($nameKey !== '') {
                    $prevOwnedNames[$nameKey] = true;
                }
            }
        }

        return [
            'owned' => array_values($owned),
            'prevowned' => array_values($prevOwned),
            'owned_names' => $ownedNames,
            'prevowned_names' => $prevOwnedNames,
        ];
    }

    /**
     * @return array{ids: list<int>, error: ?string, status?: int}
     */
    private function fetchOwnedBggIds(User $user): array
    {
        return $this->fetchCollectionBggIds($user, ['own' => 1]);
    }

    /**
     * @param  array<string, int|string>  $statusFilters  p.ej. ['own' => 1] o ['prevowned' => 1]
     * @return array{ids: list<int>, error: ?string, status?: int}
     */
    private function fetchCollectionBggIds(User $user, array $statusFilters): array
    {
        $username = trim((string) $user->bgg_username);
        $apiKey = config('services.bgg.api_key');
        if (empty($apiKey)) {
            return ['ids' => [], 'error' => 'BGG_API_KEY no configurada.', 'status' => 500];
        }
        if ($username === '') {
            return ['ids' => [], 'error' => 'No hay usuario BGG conectado.', 'status' => 422];
        }

        $cookie = $this->authCookieHeader((string) ($user->bgg_session ?? ''));
        $params = array_merge([
            'username' => $username,
            'stats' => 0,
            'brief' => 1,
            'showprivate' => 1,
        ], $statusFilters);

        $response = $this->fetchWithRetry(
            self::BGG_API_URL.'/collection',
            $params,
            $apiKey,
            $cookie !== '' ? $cookie : null,
        );
        if (!$response) {
            return [
                'ids' => [],
                'error' => 'BGG está procesando la colección, inténtalo de nuevo en unos segundos.',
                'status' => 202,
            ];
        }
        if ($response->failed()) {
            Log::warning('BGG collection fetch failed', [
                'username' => $username,
                'status' => $response->status(),
                'body' => substr($response->body(), 0, 300),
            ]);

            return [
                'ids' => [],
                'error' => 'Error al obtener la colección de BGG (HTTP '.$response->status().').',
                'status' => $response->status() >= 400 ? $response->status() : 502,
            ];
        }

        $ids = [];
        $data = @simplexml_load_string($response->body());
        if ($data !== false && isset($data->item)) {
            foreach ($data->item as $item) {
                $bggId = (int) $item['objectid'];
                if ($bggId > 0) {
                    $ids[$bggId] = $bggId;
                }
            }
        }

        return ['ids' => array_values($ids), 'error' => null];
    }

    /**
     * @return array{success: bool, message?: string, session_expired?: bool}
     */
    private function markGameAsPreviouslyOwnedOnBgg(User $user, int $bggId): array
    {
        $session = $user->bgg_session;
        if (!$session) {
            return [
                'success' => false,
                'message' => 'Sesión de BGG no disponible.',
                'session_expired' => true,
            ];
        }

        $headers = $this->bggWriteHeaders($user, $bggId);
        $collId = $this->resolveCollId($user, $bggId, null, $headers);
        if ($collId) {
            return $this->setBggCollectionStatus($headers, $bggId, $collId, false, true);
        }

        $addResponse = $this->requestBggAddItem($user, $bggId);
        if ($addResponse) {
            $headers = $this->mergeSetCookiesIntoHeaders($headers, $addResponse);
        }

        $blocked = $addResponse && (
            in_array($addResponse->status(), [403, 429], true)
            || $this->looksLikeBggBlockedOrLogin($addResponse->body())
        );

        if ($blocked) {
            if ($this->isBggIdPrevOwnedByUser((string) $user->bgg_username, $bggId)) {
                return ['success' => true];
            }

            return [
                'success' => false,
                'message' => 'BGG bloqueó temporalmente la escritura (HTTP '.($addResponse->status() ?: 403).'). Espera y reintenta solo los fallidos.',
                'rate_limited' => true,
            ];
        }

        $collId = $this->resolveCollId($user, $bggId, $addResponse?->body(), $headers);
        if (!$collId) {
            return [
                'success' => false,
                'message' => 'No se pudo crear/actualizar el ítem en BGG.',
            ];
        }

        return $this->setBggCollectionStatus($headers, $bggId, $collId, false, true);
    }

    /**
     * @return array{success: bool, message?: string, session_expired?: bool}
     */
    private function addGameToBggCollection(User $user, int $bggId): array
    {
        $session = $user->bgg_session;
        if (!$session) {
            return [
                'success' => false,
                'message' => 'Sesión de BGG no disponible.',
                'session_expired' => true,
            ];
        }

        $headers = $this->bggWriteHeaders($user, $bggId);
        if (($headers['Cookie'] ?? '') === '') {
            return [
                'success' => false,
                'message' => 'La sesión de BGG no tiene cookies válidas. Vuelve a conectar la cuenta en el perfil.',
                'session_expired' => true,
            ];
        }

        // Cloudflare bloquea POST /api/collectionitems. El alta va por
        // geekcollection.php (GET primero, que el WAF suele dejar pasar).
        $addResponse = $this->requestBggAddItem($user, $bggId);
        if ($addResponse) {
            $headers = $this->mergeSetCookiesIntoHeaders($headers, $addResponse);
        }

        $addOk = $addResponse
            && ($addResponse->successful() || $addResponse->status() === 200)
            && !$this->looksLikeBggBlockedOrLogin($addResponse->body());

        if ($addOk) {
            Log::info('BGG geekcollection additem response', [
                'bgg_id' => $bggId,
                'status' => $addResponse->status(),
                'body' => substr($addResponse->body(), 0, 400),
            ]);

            $collId = $this->resolveCollId($user, $bggId, $addResponse->body(), $headers);
            if ($collId) {
                $this->setBggCollectionStatus($headers, $bggId, $collId, true, false);

                return ['success' => true];
            }

            if ($this->isBggIdOwnedByUser((string) $user->bgg_username, $bggId)) {
                return ['success' => true];
            }

            return [
                'success' => false,
                'message' => 'BGG aceptó el alta (HTTP 200) pero no se pudo confirmar el ítem. Reintenta este juego.',
            ];
        }

        if ($this->isBggIdOwnedByUser((string) $user->bgg_username, $bggId)) {
            return ['success' => true];
        }

        $status = $addResponse?->status() ?? 0;
        if ($addResponse && $this->looksLikeBggBlockedOrLogin($addResponse->body())) {
            $status = $status === 200 ? 403 : $status;
        }

        $message = in_array($status, [403, 429], true)
            ? 'BGG bloqueó temporalmente la escritura (HTTP '.$status.'). Espera y reintenta solo los fallidos.'
            : ($status > 0
                ? 'BGG rechazó la alta del juego (HTTP '.$status.').'
                : 'No se pudo contactar con BoardGameGeek para exportar.');

        Log::warning('BGG add game failed', [
            'bgg_id' => $bggId,
            'status' => $status,
            'cookie_names' => $this->cookieNames((string) ($headers['Cookie'] ?? '')),
            'headers' => $addResponse ? $this->bggResponseHeaderSnapshot($addResponse) : [],
            'body' => substr((string) ($addResponse?->body() ?? ''), 0, 4000),
        ]);

        return [
            'success' => false,
            'message' => $message,
            'rate_limited' => in_array($status, [403, 429], true),
        ];
    }

    private function bggWriteHeaders(User $user, int $bggId): array
    {
        // Solo cookies de sesión BGG. Las de Cloudflare (cf_clearance, __cf_bm)
        // caducan y, reenviadas, provocan 403 en todas las escrituras.
        return [
            'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
            'Cookie' => $this->authCookieHeader((string) $user->bgg_session),
            'Accept' => 'application/json, text/javascript, */*; q=0.01',
            'Accept-Language' => 'en-US,en;q=0.9,es;q=0.8',
            'X-Requested-With' => 'XMLHttpRequest',
            'Origin' => 'https://boardgamegeek.com',
            'Referer' => 'https://boardgamegeek.com/collection/user/'.trim((string) $user->bgg_username),
        ];
    }

    /**
     * Visita la ficha del juego para “calentar” cookies/WAF antes de escribir.
     *
     * @return array<string, string>
     */
    private function warmUpBggWriteSession(User $user, int $bggId): array
    {
        $headers = $this->bggWriteHeaders($user, $bggId);
        $pageHeaders = $headers;
        $pageHeaders['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8';
        unset($pageHeaders['X-Requested-With']);

        try {
            $response = Http::timeout(30)
                ->withHeaders($pageHeaders)
                ->get('https://boardgamegeek.com/boardgame/'.$bggId);

            return $this->mergeSetCookiesIntoHeaders($headers, $response);
        } catch (\Throwable $e) {
            Log::info('BGG warm-up request failed', [
                'bgg_id' => $bggId,
                'error' => $e->getMessage(),
            ]);

            return $headers;
        }
    }

    /**
     * @param  array<string, string>  $headers
     * @return array<string, string>
     */
    private function mergeSetCookiesIntoHeaders(array $headers, \Illuminate\Http\Client\Response $response): array
    {
        if ($response->status() >= 400) {
            return $headers;
        }

        $extra = $this->extractSessionCookie($response);
        if ($extra === null || $extra === '') {
            return $headers;
        }

        $jar = $this->parseCookieMap((string) ($headers['Cookie'] ?? ''));
        foreach ($this->parseCookieMap($extra) as $name => $value) {
            $jar[$name] = $value;
        }

        $joined = $this->joinAuthCookies($jar);
        if ($joined !== null) {
            $headers['Cookie'] = $joined;
        }

        return $headers;
    }

    /**
     * @return array<string, string>
     */
    private function parseCookieMap(string $header): array
    {
        $byName = [];
        foreach (explode(';', $header) as $part) {
            $part = trim($part);
            if ($part === '' || !str_contains($part, '=')) {
                continue;
            }
            [$name, $value] = explode('=', $part, 2);
            $name = trim($name);
            $value = trim($value);
            if (!$this->isBggAuthCookieName($name) || $this->isDiscardableCookieValue($value)) {
                continue;
            }
            $byName[$name] = $value;
        }

        return $byName;
    }

    private function authCookieHeader(string $raw): string
    {
        return $this->joinAuthCookies($this->parseCookieMap($raw)) ?? '';
    }

    /**
     * @param  array<string, string>  $byName
     */
    private function joinAuthCookies(array $byName): ?string
    {
        if ($byName === []) {
            return null;
        }

        $parts = [];
        foreach ($byName as $name => $value) {
            $parts[] = $name.'='.$value;
        }
        $joined = implode('; ', $parts);

        $lower = strtolower($joined);
        $hasAuth = str_contains($lower, 'bggusername=')
            || str_contains($lower, 'bgg_username=')
            || str_contains($lower, 'sessionid=')
            || str_contains($lower, 'bggpassword=')
            || str_contains($lower, 'bgg_password=');

        return $hasAuth ? $joined : null;
    }

    private function isBggAuthCookieName(string $name): bool
    {
        return in_array(strtolower($name), [
            'sessionid',
            'bggusername',
            'bggpassword',
            'bgg_username',
            'bgg_password',
        ], true);
    }

    private function isDiscardableCookieValue(string $value): bool
    {
        $value = trim($value);

        return $value === '' || strtolower($value) === 'deleted';
    }

    /**
     * @return list<string>
     */
    private function cookieNames(string $header): array
    {
        return array_keys($this->parseCookieMap($header));
    }

    /**
     * @return array<string, mixed>
     */
    private function bggResponseHeaderSnapshot(\Illuminate\Http\Client\Response $response): array
    {
        $keys = ['server', 'cf-ray', 'cf-mitigated', 'content-type', 'cf-cache-status', 'refresh', 'location'];
        $snapshot = [];
        foreach ($keys as $key) {
            $snapshot[$key] = $response->header($key);
        }
        $snapshot['all_header_keys'] = array_keys($response->headers());

        return $snapshot;
    }

    private function looksLikeBggBlockedOrLogin(string $body): bool
    {
        $lower = strtolower($body);

        return str_contains($lower, 'cf-browser-verification')
            || str_contains($lower, 'just a moment')
            || str_contains($lower, 'attention required')
            || str_contains($lower, 'challenge-platform')
            || str_contains($lower, 'must be logged in')
            || str_contains($lower, 'not logged')
            || (str_contains($lower, 'sign in') && str_contains($lower, 'password'));
    }

    /**
     * @param  array{own?: bool, prevowned?: bool}  $status
     * @param  array<string, string>  $headers
     */
    private function postBggCollectionItem(array $headers, int $bggId, array $status): ?\Illuminate\Http\Client\Response
    {
        // Sin Bearer: este endpoint es de sesión web, no de XML API.
        $requestHeaders = array_merge($headers, [
            'Content-Type' => 'application/json',
            'Accept' => 'application/json',
        ]);
        unset($requestHeaders['Authorization']);

        try {
            return Http::timeout(30)
                ->withHeaders($requestHeaders)
                ->post('https://boardgamegeek.com/api/collectionitems', [
                    'objecttype' => 'thing',
                    'objectid' => $bggId,
                    'status' => $status,
                ]);
        } catch (\Throwable $e) {
            Log::warning('BGG api/collectionitems request failed', [
                'bgg_id' => $bggId,
                'error' => $e->getMessage(),
            ]);

            return null;
        }
    }

    /**
     * @param  array<string, string>  $headers
     */
    private function requestBggAddItem(User $user, int $bggId): ?\Illuminate\Http\Client\Response
    {
        $jar = $this->sessionCookieJar($user);
        $headers = $this->bggWriteHeaders($user, $bggId);
        unset($headers['Cookie']);

        $query = [
            'action' => 'additem',
            'objecttype' => 'thing',
            'objectid' => $bggId,
            'ajax' => 1,
            'instanceid' => 0,
        ];

        try {
            $getHeaders = $headers;
            unset($getHeaders['X-Requested-With'], $getHeaders['Origin']);

            $get = Http::timeout(30)
                ->withOptions(['cookies' => $jar])
                ->withHeaders($getHeaders)
                ->get('https://boardgamegeek.com/geekcollection.php', $query);

            Log::info('BGG additem GET', [
                'bgg_id' => $bggId,
                'status' => $get->status(),
                'headers' => $this->bggResponseHeaderSnapshot($get),
                'body' => substr($get->body(), 0, 4000),
            ]);

            if ($get->status() === 200 && !$this->looksLikeBggBlockedOrLogin($get->body())) {
                return $get;
            }

            return Http::timeout(30)
                ->withOptions(['cookies' => $jar])
                ->asForm()
                ->withHeaders($headers)
                ->post('https://boardgamegeek.com/geekcollection.php', $query);
        } catch (\Throwable $e) {
            Log::warning('BGG geekcollection additem request failed', [
                'bgg_id' => $bggId,
                'error' => $e->getMessage(),
            ]);

            return null;
        }
    }

    /**
     * Obtiene collid desde el body de respuesta y, si hace falta, consultando
     * la colección (XML + JSON autenticado + ficha HTML) con reintentos.
     *
     * @param  array<string, string>|null  $writeHeaders
     */
    private function resolveCollId(
        User $user,
        int $bggId,
        ?string $responseBody = null,
        ?array $writeHeaders = null,
        bool $patient = false,
    ): ?int {
        if (is_string($responseBody) && $responseBody !== '') {
            $fromBody = $this->extractCollId($responseBody);
            if ($fromBody) {
                return $fromBody;
            }
        }

        $attempts = $patient ? 5 : 3;

        for ($attempt = 0; $attempt < $attempts; $attempt++) {
            if ($attempt > 0) {
                sleep($patient ? 2 : 1);
            }

            $collId = $this->findCollectionCollId($user, $bggId);
            if ($collId) {
                return $collId;
            }

            $collId = $this->findCollIdViaJsonApi($user, $bggId, $writeHeaders);
            if ($collId) {
                return $collId;
            }

            $collId = $this->findCollIdFromGamePage($user, $bggId, $writeHeaders);
            if ($collId) {
                return $collId;
            }
        }

        return null;
    }

    private function findCollectionCollId(User $user, int $bggId): ?int
    {
        $username = trim((string) $user->bgg_username);
        $apiKey = config('services.bgg.api_key');
        if ($username === '' || $bggId <= 0) {
            return null;
        }

        $headers = [
            'Accept' => 'application/xml',
            'User-Agent' => self::IMAGE_USER_AGENT,
        ];
        if (!empty($apiKey)) {
            $headers['Authorization'] = 'Bearer '.$apiKey;
        }
        // Cookie de sesión: necesaria si la colección es privada o BGG exige auth.
        if (filled($user->bgg_session)) {
            $headers['Cookie'] = $this->authCookieHeader((string) $user->bgg_session);
        }

        $response = null;
        for ($attempt = 0; $attempt < self::MAX_RETRIES; $attempt++) {
            $response = Http::timeout(30)
                ->withHeaders($headers)
                ->get(self::BGG_API_URL.'/collection', [
                    'username' => $username,
                    'id' => $bggId,
                    'showprivate' => 1,
                ]);

            if ($response->status() !== 202) {
                break;
            }

            sleep(self::RETRY_DELAY_SECONDS);
        }

        if (!$response || $response->failed()) {
            return null;
        }

        $data = @simplexml_load_string($response->body());
        if ($data === false || !isset($data->item)) {
            return null;
        }

        foreach ($data->item as $item) {
            if ((int) $item['objectid'] === $bggId) {
                $collId = (int) ($item['collid'] ?? 0);

                return $collId > 0 ? $collId : null;
            }
        }

        return null;
    }

    private function findCollIdViaJsonApi(User $user, int $bggId, ?array $writeHeaders = null): ?int
    {
        if (!filled($user->bgg_session) || $bggId <= 0) {
            return null;
        }

        try {
            $headers = $writeHeaders ?? $this->bggWriteHeaders($user, $bggId);
            $response = Http::timeout(30)
                ->withHeaders($headers)
                ->get('https://boardgamegeek.com/api/collectionitems', [
                    'objecttype' => 'thing',
                    'objectid' => $bggId,
                ]);

            if ($response->failed()) {
                return null;
            }

            return $this->extractCollId($response->body());
        } catch (\Throwable $e) {
            return null;
        }
    }

    /**
     * @param  array<string, string>|null  $writeHeaders
     */
    private function findCollIdFromGamePage(User $user, int $bggId, ?array $writeHeaders = null): ?int
    {
        if (!filled($user->bgg_session) || $bggId <= 0) {
            return null;
        }

        try {
            $headers = $writeHeaders ?? $this->bggWriteHeaders($user, $bggId);
            $headers['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8';
            unset($headers['X-Requested-With']);

            $response = Http::timeout(30)
                ->withHeaders($headers)
                ->get('https://boardgamegeek.com/boardgame/'.$bggId);

            if ($response->failed() || $this->looksLikeBggBlockedOrLogin($response->body())) {
                return null;
            }

            return $this->extractCollId($response->body());
        } catch (\Throwable $e) {
            return null;
        }
    }

    /**
     * @return array{success: bool, message?: string}
     */
    private function setBggCollectionStatus(
        array $headers,
        int $bggId,
        ?int $collId,
        bool $own,
        bool $prevOwned,
    ): array {
        if (!$collId) {
            return [
                'success' => false,
                'message' => 'No se pudo obtener el collid de BGG.',
            ];
        }

        try {
            $saveResponse = null;
            for ($attempt = 0; $attempt < 3; $attempt++) {
                if ($attempt > 0) {
                    sleep($attempt * 2);
                }

                $saveResponse = Http::timeout(30)
                    ->asForm()
                    ->withHeaders($headers)
                    ->post('https://boardgamegeek.com/geekcollection.php', [
                        'action' => 'savedata',
                        'ajax' => 1,
                        'collid' => $collId,
                        'fieldname' => 'status',
                        'own' => $own ? 1 : 0,
                        'prevowned' => $prevOwned ? 1 : 0,
                        'objecttype' => 'thing',
                        'objectid' => $bggId,
                    ]);

                if ($saveResponse->successful() || $saveResponse->status() === 200) {
                    return ['success' => true];
                }

                if (!in_array($saveResponse->status(), [403, 429, 502, 503], true)) {
                    break;
                }
            }

            return [
                'success' => false,
                'message' => 'No se pudo actualizar el estado en BGG'
                    .($saveResponse ? ' (HTTP '.$saveResponse->status().')' : '').'.',
            ];
        } catch (\Throwable $e) {
            return [
                'success' => false,
                'message' => 'Error al actualizar el estado en BGG.',
            ];
        }
    }

    /**
     * @deprecated Use setBggCollectionStatus()
     * @return array{success: bool, message?: string}
     */
    private function markBggItemAsOwned(array $headers, int $bggId, string $body, ?int $collId = null): array
    {
        return $this->setBggCollectionStatus(
            $headers,
            $bggId,
            $collId ?? $this->extractCollId($body),
            true,
            false,
        );
    }

    private function extractCollId(string $body): ?int
    {
        $body = trim($body);
        if ($body === '') {
            return null;
        }

        if (ctype_digit($body)) {
            $id = (int) $body;

            return $id > 0 ? $id : null;
        }

        if (preg_match('/\bcollid["\'\s:=]+(\d+)/i', $body, $m)) {
            return (int) $m[1];
        }
        if (preg_match('/\bcollectionid["\'\s:=]+(\d+)/i', $body, $m)) {
            return (int) $m[1];
        }
        if (preg_match('/editownership_(\d+)/', $body, $m)) {
            return (int) $m[1];
        }
        if (preg_match('/data-collid=["\']?(\d+)/i', $body, $m)) {
            return (int) $m[1];
        }
        if (preg_match('#/collection/item/(\d+)#i', $body, $m)) {
            return (int) $m[1];
        }

        $json = json_decode($body, true);
        if (is_array($json)) {
            $found = $this->extractCollIdFromArray($json);
            if ($found) {
                return $found;
            }
        }

        return null;
    }

    private function extractCollIdFromArray(array $data): ?int
    {
        foreach (['collid', 'collectionid', 'collection_id', 'id'] as $key) {
            if (isset($data[$key]) && is_numeric($data[$key]) && (int) $data[$key] > 0) {
                // Evitar confundir objectid del juego con collid.
                if ($key === 'id' && isset($data['objectid']) && (int) $data['id'] === (int) $data['objectid']) {
                    continue;
                }

                return (int) $data[$key];
            }
        }

        foreach (['item', 'items', 'data', 'collectionitems'] as $nestedKey) {
            if (!isset($data[$nestedKey]) || !is_array($data[$nestedKey])) {
                continue;
            }

            $nested = $data[$nestedKey];
            if (array_is_list($nested)) {
                foreach ($nested as $entry) {
                    if (!is_array($entry)) {
                        continue;
                    }
                    $found = $this->extractCollIdFromArray($entry);
                    if ($found) {
                        return $found;
                    }
                }
            } else {
                $found = $this->extractCollIdFromArray($nested);
                if ($found) {
                    return $found;
                }
            }
        }

        return null;
    }

    private function extractSessionCookie(\Illuminate\Http\Client\Response $response): ?string
    {
        $parts = [];

        foreach ($response->cookies() as $cookie) {
            $name = $cookie->getName();
            $value = (string) $cookie->getValue();
            if (!$this->isBggAuthCookieName($name) || $this->isDiscardableCookieValue($value)) {
                continue;
            }
            $parts[] = $name.'='.$value;
        }

        if ($parts === []) {
            $rawHeaders = $response->headers()['Set-Cookie'] ?? [];
            foreach ((array) $rawHeaders as $header) {
                if (!is_string($header) || $header === '') {
                    continue;
                }
                $pair = explode(';', $header, 2)[0] ?? '';
                if (!str_contains($pair, '=')) {
                    continue;
                }
                [$name, $value] = explode('=', $pair, 2);
                $name = trim($name);
                $value = trim($value);
                if (!$this->isBggAuthCookieName($name) || $this->isDiscardableCookieValue($value)) {
                    continue;
                }
                $parts[] = $name.'='.$value;
            }
        }

        if ($parts === []) {
            return null;
        }

        $joined = implode('; ', array_unique($parts));

        return $this->joinAuthCookies($this->parseCookieMap($joined));
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

        $light = $request->boolean('light');
        $limit = max(1, min((int) $request->input('limit', $light ? 8 : 10), 15));
        $exact = $request->boolean('exact');

        $apiKey = config('services.bgg.api_key');
        $headers = [
            'Accept' => 'application/xml',
            'User-Agent' => self::IMAGE_USER_AGENT,
        ];
        if ($apiKey) {
            $headers['Authorization'] = 'Bearer ' . $apiKey;
        }

        $searchParams = [
            'query' => $query,
            'type' => 'boardgame,boardgameexpansion',
        ];
        if ($exact) {
            $searchParams['exact'] = 1;
        }

        try {
            $response = Http::timeout($light ? 15 : 30)->withHeaders($headers)
                ->get(self::BGG_API_URL . '/search', $searchParams);
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

        $games = array_slice($this->parseSearchXml($response->body()), 0, $limit);

        if (!empty($games)) {
            // En modo light pedimos menos detalles (miniaturas) para ganar velocidad.
            $detailCount = $light ? min(5, count($games)) : min(10, count($games));
            $topIds = array_slice(array_map(fn ($g) => $g['bgg_id'], $games), 0, $detailCount);
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

    private function fetchWithRetry(string $url, array $params, string $apiKey, ?string $cookie = null)
    {
        $response = null;

        for ($attempt = 0; $attempt < self::MAX_RETRIES; $attempt++) {
            $headers = [
                'Accept' => 'application/xml',
                'Authorization' => 'Bearer '.$apiKey,
                'User-Agent' => self::IMAGE_USER_AGENT,
            ];
            if (is_string($cookie) && $cookie !== '') {
                $headers['Cookie'] = $cookie;
            }

            $response = Http::timeout(45)->withHeaders($headers)->get($url, $params);
            $status = $response->status();
            $pendingXml = $status === 200 && $this->collectionResponseIsPending((string) $response->body());

            if ($status === 202 || $status === 429 || $status === 503 || $pendingXml) {
                sleep($status === 429 ? 5 : self::RETRY_DELAY_SECONDS);
                continue;
            }

            return $response;
        }

        if ($response && in_array($response->status(), [202, 429, 503], true)) {
            return null;
        }
        if ($response && $response->status() === 200 && $this->collectionResponseIsPending((string) $response->body())) {
            return null;
        }

        return $response;
    }

    private function collectionResponseIsPending(string $body): bool
    {
        if ($body === '' || str_contains($body, '<item')) {
            return false;
        }

        $lower = strtolower($body);

        return str_contains($body, '<message')
            || str_contains($lower, 'try again later')
            || str_contains($lower, 'will be processed');
    }

    private function collectionAuthCookie(string $username): ?string
    {
        $user = request()->user();
        if (!$user instanceof User || !filled($user->bgg_session)) {
            return null;
        }
        if (strcasecmp(trim((string) $user->bgg_username), trim($username)) !== 0) {
            return null;
        }
        $cookie = $this->authCookieHeader((string) $user->bgg_session);

        return $cookie !== '' ? $cookie : null;
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
        $seen = [];

        foreach ($data->item as $item) {
            $bggId = (int) $item['objectid'];
            // La colección de BGG puede contener el mismo juego repetido
            // (varias copias, distintos collid). Deduplicamos por bgg_id para
            // que el total mostrado coincida con lo que realmente se importa.
            if (!$bggId || isset($seen[$bggId])) {
                continue;
            }
            $seen[$bggId] = true;

            $stats = $item->stats ?? null;
            $rating = $stats?->rating ?? null;

            $games[] = [
                'bgg_id' => $bggId,
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
