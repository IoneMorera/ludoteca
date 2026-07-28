<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class VisionController extends Controller
{
    /**
     * Identifica un juego de mesa a partir de una imagen usando OpenAI Vision.
     *
     * Espera un upload `image` (multipart) o `image_base64` en JSON.
     * Devuelve {candidates: [{name, year, confidence, reasoning}]} y, opcionalmente,
     * resultados de BGG si `lookup_bgg` viene a true (por defecto).
     */
    public function recognize(Request $request): JsonResponse
    {
        $request->validate([
            'image' => 'sometimes|file|image|max:8192',
            'image_base64' => 'sometimes|string',
            'lookup_bgg' => 'sometimes|boolean',
        ]);

        $apiKey = config('services.openai.api_key');
        if (empty($apiKey)) {
            return response()->json([
                'message' => 'OPENAI_API_KEY no configurada en el servidor.',
            ], 503);
        }

        $imageData = null;
        $mime = 'image/jpeg';

        if ($request->hasFile('image')) {
            $file = $request->file('image');
            $imageData = base64_encode(file_get_contents($file->getRealPath()));
            $mime = $file->getMimeType() ?: 'image/jpeg';
        } elseif ($request->filled('image_base64')) {
            $imageData = $request->input('image_base64');
            $mime = $request->input('image_mime', 'image/jpeg');
        }

        if (!$imageData) {
            return response()->json([
                'message' => 'Se requiere image o image_base64.',
            ], 422);
        }

        $model = config('services.openai.model', 'gpt-4o');

        $prompt = <<<'PROMPT'
Identifica el juego de mesa que aparece en la imagen (caja, portada, carta o
componente). Responde EXCLUSIVAMENTE con un objeto JSON con esta forma exacta,
sin texto adicional ni Markdown:

{
  "candidates": [
    {"name": "Nombre canónico en inglés", "year": 2020, "confidence": 0.85, "reasoning": "breve"}
  ]
}

Reglas:
- Usa el nombre oficial en inglés tal como aparece en BoardGameGeek cuando lo
  conozcas (p. ej. "Catan", "Ticket to Ride", "Wingspan").
- Si el título visible está en otro idioma, incluye también la variante en
  inglés como candidato separado si es distinta.
- Incluye el año de publicación si es visible en la caja o lo conoces con
  seguridad; si no, usa null.
- Devuelve hasta 3 candidatos ordenados por confianza descendente.
- Si no reconoces nada, devuelve {"candidates": []}.
PROMPT;

        try {
            $response = Http::timeout(45)
                ->withHeaders([
                    'Authorization' => 'Bearer ' . $apiKey,
                    'Content-Type' => 'application/json',
                ])
                ->post('https://api.openai.com/v1/chat/completions', [
                    'model' => $model,
                    'temperature' => 0,
                    'response_format' => ['type' => 'json_object'],
                    'messages' => [[
                        'role' => 'user',
                        'content' => [
                            ['type' => 'text', 'text' => $prompt],
                            [
                                'type' => 'image_url',
                                'image_url' => [
                                    'url' => "data:{$mime};base64,{$imageData}",
                                    'detail' => 'high',
                                ],
                            ],
                        ],
                    ]],
                ]);
        } catch (\Throwable $e) {
            Log::warning('vision.recognize OpenAI call failed', [
                'error' => $e->getMessage(),
            ]);
            return response()->json([
                'message' => 'No se pudo contactar con el servicio de visi\u00f3n.',
            ], 502);
        }

        if ($response->failed()) {
            Log::warning('vision.recognize OpenAI returned error', [
                'status' => $response->status(),
                'body' => $response->body(),
            ]);
            return response()->json([
                'message' => 'Error en el servicio de visi\u00f3n.',
                'status' => $response->status(),
            ], 502);
        }

        $content = $response->json('choices.0.message.content');
        $parsed = $this->parseJson($content);

        $candidates = collect($parsed['candidates'] ?? [])
            ->filter(fn ($c) => is_array($c) && !empty($c['name']))
            ->map(fn ($c) => [
                'name' => (string) $c['name'],
                'year' => isset($c['year']) ? (int) $c['year'] : null,
                'confidence' => isset($c['confidence']) ? (float) $c['confidence'] : null,
                'reasoning' => $c['reasoning'] ?? null,
            ])
            ->take(3)
            ->values()
            ->all();

        $bggMatches = [];
        if ($request->boolean('lookup_bgg', true) && !empty($candidates)) {
            $bggMatches = $this->lookupBggForCandidates($candidates);
        }

        return response()->json([
            'candidates' => $candidates,
            'bgg_games' => $bggMatches,
        ]);
    }

    private function parseJson(?string $content): array
    {
        if (empty($content)) {
            return ['candidates' => []];
        }
        $decoded = json_decode($content, true);
        if (is_array($decoded)) {
            return $decoded;
        }
        return ['candidates' => []];
    }

    /**
     * Busca en BGG para hasta 3 candidatos de la IA y fusiona sin duplicados.
     */
    private function lookupBggForCandidates(array $candidates): array
    {
        $merged = [];
        $seenIds = [];

        foreach (array_slice($candidates, 0, 3) as $candidate) {
            $name = trim((string) ($candidate['name'] ?? ''));
            if ($name === '') {
                continue;
            }

            foreach ($this->lookupBgg($name) as $game) {
                $bggId = $game['bgg_id'] ?? null;
                if ($bggId !== null) {
                    if (isset($seenIds[$bggId])) {
                        continue;
                    }
                    $seenIds[$bggId] = true;
                }
                $merged[] = $game;
            }
        }

        return $merged;
    }

    /**
     * Reutiliza la b\u00fasqueda de BGG existente para devolver match real
     * (con bgg_id, im\u00e1genes, etc.) a partir del nombre identificado.
     */
    private function lookupBgg(string $name): array
    {
        try {
            $bggController = app(BggController::class);
            $request = request()->duplicate();
            $request->merge(['query' => $name]);
            $response = $bggController->search($request);
            $data = $response->getData(true);
            return $data['games'] ?? [];
        } catch (\Throwable $e) {
            Log::warning('vision.recognize BGG lookup failed', [
                'name' => $name,
                'error' => $e->getMessage(),
            ]);
            return [];
        }
    }
}
