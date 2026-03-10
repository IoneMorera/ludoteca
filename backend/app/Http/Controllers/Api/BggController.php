<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Categoria;
use App\Models\Juego;
use App\Models\Propietario;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Storage;

class BggController extends Controller
{
    private const BGG_API_URL = 'https://boardgamegeek.com/xmlapi2';
    private const MAX_RETRIES = 5;
    private const RETRY_DELAY_SECONDS = 2;

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

        $categoria = Categoria::firstOrCreate(
            ['nombre' => 'Importado BGG'],
            ['descripcion' => 'Juegos importados desde BoardGameGeek']
        );

        $propietario = $this->resolveOwner($request->input('bgg_username'));

        $imported = 0;
        $skipped = 0;

        foreach ($request->input('games') as $game) {
            $result = Juego::firstOrCreate(
                ['bgg_id' => $game['bgg_id']],
                [
                    'nombre' => $game['name'],
                    'num_jugadores_min' => $game['min_players'] ?? null,
                    'num_jugadores_max' => $game['max_players'] ?? null,
                    'categoria_id' => $categoria->id,
                    'estado' => 'disponible',
                ]
            );

            if ($result->wasRecentlyCreated) {
                $imported++;
                $localPath = $this->downloadCover($game);
                if ($localPath) {
                    $result->update(['imagen' => $localPath]);
                }
                if ($propietario) {
                    $result->propietarios()->syncWithoutDetaching([$propietario->id]);
                }
            } else {
                $skipped++;
            }
        }

        return response()->json([
            'imported' => $imported,
            'skipped' => $skipped,
        ]);
    }

    public function importExpansions(Request $request): JsonResponse
    {
        $request->validate([
            'expansions' => 'required|array|min:1',
            'expansions.*.bgg_id' => 'required|integer',
            'expansions.*.name' => 'required|string',
            'bgg_username' => 'nullable|string',
        ]);

        $apiKey = config('services.bgg.api_key');
        $categoria = Categoria::firstOrCreate(
            ['nombre' => 'Importado BGG'],
            ['descripcion' => 'Juegos importados desde BoardGameGeek']
        );

        $propietario = $this->resolveOwner($request->input('bgg_username'));

        $imported = 0;
        $skipped = 0;
        $omitted = [];

        foreach ($request->input('expansions') as $expansion) {
            $existingExpansion = Juego::where('bgg_id', $expansion['bgg_id'])->first();
            if ($existingExpansion) {
                $skipped++;
                continue;
            }

            $baseGameBggId = $this->findBaseGameBggId($expansion['bgg_id'], $apiKey);

            if (!$baseGameBggId) {
                $omitted[] = $expansion['name'];
                continue;
            }

            $baseGame = Juego::where('bgg_id', $baseGameBggId)->first();
            if (!$baseGame) {
                $omitted[] = $expansion['name'] . ' (juego base BGG #' . $baseGameBggId . ' no encontrado)';
                continue;
            }

            $juego = Juego::create([
                'nombre' => $expansion['name'],
                'bgg_id' => $expansion['bgg_id'],
                'num_jugadores_min' => $expansion['min_players'] ?? null,
                'num_jugadores_max' => $expansion['max_players'] ?? null,
                'categoria_id' => $categoria->id,
                'estado' => 'disponible',
                'juego_base_id' => $baseGame->id,
            ]);

            $localPath = $this->downloadCover($expansion);
            if ($localPath) {
                $juego->update(['imagen' => $localPath]);
            }

            if ($propietario) {
                $juego->propietarios()->syncWithoutDetaching([$propietario->id]);
            }

            $imported++;
        }

        return response()->json([
            'imported' => $imported,
            'skipped' => $skipped,
            'omitted' => $omitted,
            'omitted_count' => count($omitted),
        ]);
    }

    /**
     * Si el username BGG consultado coincide con el del usuario logueado,
     * devuelve su propietario principal (creado al registrarse).
     */
    private function resolveOwner(?string $bggUsername): ?Propietario
    {
        if (!$bggUsername) {
            return null;
        }

        $user = Auth::user();
        if (!$user || !$user->bgg_username) {
            return null;
        }

        if (strtolower($bggUsername) !== strtolower($user->bgg_username)) {
            return null;
        }

        return Propietario::where('nombre', $user->name)->first();
    }

    private function findBaseGameBggId(int $expansionBggId, ?string $apiKey): ?int
    {
        $headers = [
            'Accept' => 'application/xml',
            'User-Agent' => 'Ludoteca/1.0 (BoardGameGeek Integration)',
        ];

        if ($apiKey) {
            $headers['Authorization'] = 'Bearer ' . $apiKey;
        }

        $response = Http::timeout(15)->withHeaders($headers)
            ->get(self::BGG_API_URL . '/thing', [
                'id' => $expansionBggId,
                'type' => 'boardgameexpansion',
            ]);

        if ($response->failed()) {
            return null;
        }

        $data = @simplexml_load_string($response->body());
        if ($data === false || !isset($data->item)) {
            return null;
        }

        foreach ($data->item->link as $link) {
            if ((string) $link['type'] === 'boardgameexpansion' && (string) $link['inbound'] === 'true') {
                return (int) $link['id'];
            }
        }

        return null;
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
            'User-Agent' => 'Ludoteca/1.0 (BoardGameGeek Integration)',
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
                'User-Agent' => 'Ludoteca/1.0 (BoardGameGeek Integration)',
            ])->get($url, $params);

            if ($response->status() !== 202) {
                return $response;
            }

            sleep(self::RETRY_DELAY_SECONDS);
        }

        return null;
    }

    private function downloadCover(array $game): ?string
    {
        $imageUrl = $game['image'] ?? $game['thumbnail'] ?? null;
        if (!$imageUrl) {
            return null;
        }

        try {
            $response = Http::timeout(10)->get($imageUrl);
            if ($response->failed()) {
                return null;
            }

            $extension = pathinfo(parse_url($imageUrl, PHP_URL_PATH), PATHINFO_EXTENSION) ?: 'jpg';
            $filename = "juegos/bgg_{$game['bgg_id']}.{$extension}";

            Storage::disk('public')->put($filename, $response->body());

            return "/storage/{$filename}";
        } catch (\Throwable) {
            return null;
        }
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
