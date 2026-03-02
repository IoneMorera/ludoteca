<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Ubicacion;
use Illuminate\Http\Request;

class UbicacionController extends Controller
{
    public function index()
    {
        $ubicaciones = Ubicacion::with(['mueble.habitacion'])
            ->orderBy('id', 'desc')
            ->get();

        return response()->json($ubicaciones);
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'mueble_id' => ['required', 'exists:muebles,id'],
            'nombre' => ['required', 'string', 'max:255'],
        ]);

        $ubicacion = Ubicacion::create($data);

        return response()->json($ubicacion->load('mueble.habitacion'), 201);
    }
}

