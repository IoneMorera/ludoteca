<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Categoria;
use App\Models\Juego;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
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
                'message' => 'BGG_API_KEY no configurada. Regístrate en boardgamegeek.com/applications y añade el token en .env',
            ], 500);
        }

        $response = null;

        for ($attempt = 0; $attempt < self::MAX_RETRIES; $attempt++) {
            $response = Http::timeout(30)->withHeaders([
                'Accept' => 'application/xml',
                'Authorization' => 'Bearer ' . $apiKey,
                'User-Agent' => 'Ludoteca/1.0 (BoardGameGeek Integration)',
            ])->get(self::BGG_API_URL . '/collection', [
                'username' => $username,
                'own' => 1,
                'stats' => 1,
                'subtype' => 'boardgame',
                'excludesubtype' => 'boardgameexpansion',
            ]);

            if ($response->status() !== 202) {
                break;
            }

            sleep(self::RETRY_DELAY_SECONDS);
        }

        if (!$response || $response->status() === 202) {
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

    public function import(Request $request): JsonResponse
    {
        $request->validate([
            'games' => 'required|array|min:1',
            'games.*.bgg_id' => 'required|integer',
            'games.*.name' => 'required|string',
        ]);

        $categoria = Categoria::firstOrCreate(
            ['nombre' => 'Importado BGG'],
            ['descripcion' => 'Juegos importados desde BoardGameGeek']
        );

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
            } else {
                $skipped++;
            }
        }

        return response()->json([
            'imported' => $imported,
            'skipped' => $skipped,
        ]);
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

    public function plays(string $username): JsonResponse
    {
        $apiKey = config('services.bgg.api_key');
        if (empty($apiKey)) {
            return response()->json([
                'message' => 'BGG_API_KEY no configurada. Regístrate en boardgamegeek.com/applications y añade el token en .env',
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
