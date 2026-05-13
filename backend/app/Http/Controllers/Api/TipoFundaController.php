<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\TipoFunda;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class TipoFundaController extends Controller
{
    public function index(): JsonResponse
    {
        $tipos = TipoFunda::withCount('juegos')
            ->orderBy('alto_mm')
            ->orderBy('ancho_mm')
            ->get();

        return response()->json($tipos);
    }

    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'nombre' => ['required', 'string', 'max:255'],
            'ancho_mm' => [
                'required',
                'integer',
                'min:1',
                'max:999',
                Rule::unique('tipos_funda')->where(fn ($query) => $query
                    ->where('alto_mm', $request->input('alto_mm'))),
            ],
            'alto_mm' => ['required', 'integer', 'min:1', 'max:999'],
            'descripcion' => ['nullable', 'string'],
        ]);

        $tipo = TipoFunda::create($validated);

        return response()->json($tipo, 201);
    }

    public function show(TipoFunda $tipoFunda): JsonResponse
    {
        $tipoFunda->loadCount('juegos');

        return response()->json($tipoFunda);
    }

    public function update(Request $request, TipoFunda $tipoFunda): JsonResponse
    {
        $validated = $request->validate([
            'nombre' => ['required', 'string', 'max:255'],
            'ancho_mm' => [
                'required',
                'integer',
                'min:1',
                'max:999',
                Rule::unique('tipos_funda')->where(fn ($query) => $query
                    ->where('alto_mm', $request->input('alto_mm')))
                    ->ignore($tipoFunda->id),
            ],
            'alto_mm' => ['required', 'integer', 'min:1', 'max:999'],
            'descripcion' => ['nullable', 'string'],
        ]);

        $tipoFunda->update($validated);

        return response()->json($tipoFunda);
    }

    public function destroy(TipoFunda $tipoFunda): JsonResponse
    {
        $tipoFunda->delete();

        return response()->json(null, 204);
    }
}
