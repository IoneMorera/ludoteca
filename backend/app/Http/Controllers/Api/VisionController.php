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
            $raw = file_get_contents($file->getRealPath());
            [$imageData, $mime] = $this->prepareImagePayload(
                $raw,
                $file->getMimeType() ?: 'image/jpeg'
            );
        } elseif ($request->filled('image_base64')) {
            $rawB64 = $request->input('image_base64');
            $raw = base64_decode($rawB64, true);
            if ($raw === false) {
                return response()->json([
                    'message' => 'image_base64 no es válida.',
                ], 422);
            }
            [$imageData, $mime] = $this->prepareImagePayload(
                $raw,
                $request->input('image_mime', 'image/jpeg')
            );
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
            $response = Http::timeout(60)
                ->withHeaders([
                    'Authorization' => 'Bearer ' . $apiKey,
                    'Content-Type' => 'application/json',
                ])
                ->post('https://api.openai.com/v1/chat/completions', [
                    'model' => $model,
                    'temperature' => 0,
                    'max_tokens' => 400,
                    'response_format' => ['type' => 'json_object'],
                    'messages' => [[
                        'role' => 'user',
                        'content' => [
                            ['type' => 'text', 'text' => $prompt],
                            [
                                'type' => 'image_url',
                                'image_url' => [
                                    'url' => "data:{$mime};base64,{$imageData}",
                                    // low = mucho más rápido; suficiente para portadas
                                    'detail' => 'low',
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
                'message' => 'No se pudo contactar con el servicio de visión.',
            ], 502);
        }

        if ($response->failed()) {
            Log::warning('vision.recognize OpenAI returned error', [
                'status' => $response->status(),
                'body' => $response->body(),
            ]);
            $openAiMsg = $response->json('error.message');
            return response()->json([
                'message' => $openAiMsg
                    ? "Error en el servicio de visión: {$openAiMsg}"
                    : 'Error en el servicio de visión.',
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
            // Solo el mejor candidato: cada lookup BGG es costoso y el cliente
            // ya busca BGG por OCR en paralelo.
            $bggMatches = $this->lookupBggForCandidates(array_slice($candidates, 0, 1));
        }

        return response()->json([
            'candidates' => $candidates,
            'bgg_games' => $bggMatches,
        ]);
    }

    /**
     * Normaliza la imagen a JPEG reducido para reducir latencia/coste de Vision.
     *
     * @return array{0: string, 1: string} [base64, mime]
     */
    private function prepareImagePayload(string $raw, string $mime): array
    {
        if (!function_exists('imagecreatefromstring')) {
            return [base64_encode($raw), $mime ?: 'image/jpeg'];
        }

        $src = @imagecreatefromstring($raw);
        if ($src === false) {
            return [base64_encode($raw), $mime ?: 'image/jpeg'];
        }

        $width = imagesx($src);
        $height = imagesy($src);
        $maxSide = 1280;

        if ($width > $maxSide || $height > $maxSide) {
            if ($width >= $height) {
                $newW = $maxSide;
                $newH = (int) round($height * ($maxSide / $width));
            } else {
                $newH = $maxSide;
                $newW = (int) round($width * ($maxSide / $height));
            }
            $dst = imagecreatetruecolor($newW, $newH);
            imagecopyresampled($dst, $src, 0, 0, 0, 0, $newW, $newH, $width, $height);
            imagedestroy($src);
            $src = $dst;
        }

        ob_start();
        imagejpeg($src, null, 70);
        $jpeg = ob_get_clean();
        imagedestroy($src);

        if ($jpeg === false || $jpeg === '') {
            return [base64_encode($raw), $mime ?: 'image/jpeg'];
        }

        return [base64_encode($jpeg), 'image/jpeg'];
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
     * Busca en BGG para los candidatos de la IA y fusiona sin duplicados.
     */
    private function lookupBggForCandidates(array $candidates): array
    {
        $merged = [];
        $seenIds = [];

        foreach ($candidates as $candidate) {
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
     * Reutiliza la búsqueda de BGG existente para devolver match real
     * (con bgg_id, imágenes, etc.) a partir del nombre identificado.
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
