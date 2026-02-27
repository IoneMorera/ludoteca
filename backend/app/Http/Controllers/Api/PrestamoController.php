<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Juego;
use App\Models\Prestamo;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PrestamoController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $query = Prestamo::with('juego');

        if ($request->has('estado')) {
            $query->where('estado', $request->estado);
        }

        if ($request->has('buscar')) {
            $query->where('persona', 'like', '%' . $request->buscar . '%');
        }

        $prestamos = $query->orderByDesc('fecha_prestamo')->paginate(15);

        return response()->json($prestamos);
    }

    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'juego_id' => 'required|exists:juegos,id',
            'persona' => 'required|string|max:255',
            'fecha_prestamo' => 'required|date',
            'fecha_devolucion_prevista' => 'required|date|after:fecha_prestamo',
            'observaciones' => 'nullable|string',
        ]);

        $juego = Juego::findOrFail($validated['juego_id']);
        if ($juego->estado !== 'disponible') {
            return response()->json(['message' => 'El juego no está disponible para préstamo'], 422);
        }

        $validated['estado'] = 'activo';
        $prestamo = Prestamo::create($validated);

        $juego->update(['estado' => 'prestado']);

        $prestamo->load('juego');

        return response()->json($prestamo, 201);
    }

    public function show(Prestamo $prestamo): JsonResponse
    {
        $prestamo->load('juego.categoria');

        return response()->json($prestamo);
    }

    public function update(Request $request, Prestamo $prestamo): JsonResponse
    {
        $validated = $request->validate([
            'fecha_devolucion_prevista' => 'nullable|date',
            'observaciones' => 'nullable|string',
        ]);

        $prestamo->update($validated);
        $prestamo->load('juego');

        return response()->json($prestamo);
    }

    public function devolver(Prestamo $prestamo): JsonResponse
    {
        if ($prestamo->estado !== 'activo') {
            return response()->json(['message' => 'Este préstamo ya fue devuelto'], 422);
        }

        $prestamo->update([
            'estado' => 'devuelto',
            'fecha_devolucion_real' => now(),
        ]);

        $prestamo->juego->update(['estado' => 'disponible']);

        $prestamo->load('juego');

        return response()->json($prestamo);
    }
}
