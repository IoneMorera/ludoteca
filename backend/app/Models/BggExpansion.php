<?php

namespace App\Models;

use App\Models\Concerns\RecordsTombstone;
use Illuminate\Database\Eloquent\Model;

class BggExpansion extends Model
{
    use RecordsTombstone;

    protected $table = 'bgg_expansiones';

    protected $fillable = [
        'base_bgg_id',
        'expansion_bgg_id',
        'nombre',
        'anio',
        'imagen',
        'min_jugadores',
        'max_jugadores',
        'ignorada',
    ];

    protected $casts = [
        'base_bgg_id' => 'integer',
        'expansion_bgg_id' => 'integer',
        'anio' => 'integer',
        'min_jugadores' => 'integer',
        'max_jugadores' => 'integer',
        'ignorada' => 'boolean',
    ];
}
