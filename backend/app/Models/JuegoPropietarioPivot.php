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
    ];

    protected $casts = [
        'juego_id' => 'integer',
        'propietario_id' => 'integer',
        'ubicacion_id' => 'integer',
    ];
}
