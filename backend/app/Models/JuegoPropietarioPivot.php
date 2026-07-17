<?php

namespace App\Models;

use App\Models\Concerns\RecordsTombstone;
use Illuminate\Database\Eloquent\Model;

/**
 * Modelo "thin" para la tabla pivote `juego_propietario`.
 *
 * Permite operar sobre la tabla pivote desde el SyncController y
 * registrar tombstones al borrar filas.
 */
class JuegoPropietarioPivot extends Model
{
    use RecordsTombstone;

    protected $table = 'juego_propietario';

    protected $fillable = [
        'juego_id',
        'propietario_id',
        'ubicacion_id',
        'es_principal',
        'estado',
        'fecha_compra',
        'no_enfundar',
        'idiomas',
        'idioma_otro',
        'independiente_idioma',
        'tradumaquetado',
        'tradumaquetado_parcial',
        'tradumaquetado_parcial_notas',
        'sin_abrir',
        'print_and_play',
    ];

    protected $casts = [
        'juego_id' => 'integer',
        'propietario_id' => 'integer',
        'ubicacion_id' => 'integer',
        'es_principal' => 'boolean',
        'fecha_compra' => 'date:Y-m-d',
        'no_enfundar' => 'boolean',
        'idiomas' => 'array',
        'independiente_idioma' => 'boolean',
        'tradumaquetado' => 'boolean',
        'tradumaquetado_parcial' => 'boolean',
        'sin_abrir' => 'boolean',
        'print_and_play' => 'boolean',
    ];

    public function fundas()
    {
        return $this->hasMany(JuegoPropietarioFunda::class, 'juego_propietario_id');
    }
}
