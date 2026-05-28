<?php

namespace App\Models;

use App\Models\Concerns\RecordsTombstone;
use Illuminate\Database\Eloquent\Model;

class JuegoCategoriaPivot extends Model
{
    use RecordsTombstone;

    protected $table = 'juego_categoria';

    protected $fillable = [
        'juego_id',
        'categoria_id',
    ];

    protected $casts = [
        'juego_id' => 'integer',
        'categoria_id' => 'integer',
    ];
}
