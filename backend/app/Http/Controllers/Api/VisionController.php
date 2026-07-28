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
     * Opcional: `ocr_hint` con texto detectado por OCR (puede contener errores).
     * Devuelve {candidates, bgg_games}.
     */
    public function recognize(Request $request): JsonResponse
    {
        $request->validate([
            'image' => 'sometimes|file|image|max:12288',
            'image_base64' => 'sometimes|string',
            // form-data puede enviar 1/0 o "true"/"false"; boolean() lo normaliza.
            'lookup_bgg' => 'sometimes',
            'ocr_hint' => 'sometimes|string|max:500',
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
        $ocrHint = trim((string) $request->input('ocr_hint', ''));

        $prompt = $this->buildPrompt($ocrHint);

        try {
            $response = Http::timeout(90)
                ->withHeaders([
                    'Authorization' => 'Bearer ' . $apiKey,
                    'Content-Type' => 'application/json',
                ])
                ->post('https://api.openai.com/v1/chat/completions', [
                    'model' => $model,
                    'temperature' => 0,
                    'max_tokens' => 500,
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
            // Hasta 2 candidatos: balance precisión / latencia.
            $bggMatches = $this->lookupBggForCandidates(array_slice($candidates, 0, 2));
        }

        return response()->json([
            'candidates' => $candidates,
            'bgg_games' => $bggMatches,
        ]);
    }

    private function buildPrompt(string $ocrHint): string
    {
        $hintBlock = '';
        if ($ocrHint !== '') {
            $safe = mb_substr($ocrHint, 0, 400);
            $hintBlock = <<<HINT

Texto OCR aproximado (puede contener errores de lectura; úsalo solo como pista,
nunca como verdad absoluta):
"{$safe}"
HINT;
        }

        return <<<PROMPT
Eres un experto en juegos de mesa. Identifica EXACTAMENTE el juego cuya caja,
portada o componente aparece en la imagen.
{$hintBlock}

Responde EXCLUSIVAMENTE con un objeto JSON (sin Markdown):

{
  "candidates": [
    {"name": "Nombre oficial", "year": 2020, "confidence": 0.85, "reasoning": "breve"}
  ]
}

Reglas estrictas:
1. Lee el TÍTULO visible en la portada. El nombre debe corresponder a ESE juego,
   no a uno parecido por arte, temática o editorial.
2. Si reconoces la portada, usa el nombre canónico de BoardGameGeek en inglés
   (p. ej. "Catan", "Ticket to Ride", "Wingspan", "Brass: Birmingham").
3. Si el título está en otro idioma, pon primero el nombre BGG en inglés y,
   si difiere, un segundo candidato con el título tal como se ve.
4. NO inventes ni propongas juegos solo porque el arte se parece. Si no estás
   seguro, baja la confidence o deja candidates vacío.
5. Incluye year solo si lo ves en la caja o lo conoces con seguridad; si no, null.
6. Máximo 3 candidatos, ordenados por confianza descendente.
7. Si no puedes identificar el juego concreto, responde {"candidates": []}.
PROMPT;
    }

    /**
     * Normaliza a JPEG de calidad alta (máx. 2048px) para Vision con detail=high.
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
        $maxSide = 2048;

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
        imagejpeg($src, null, 90);
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
