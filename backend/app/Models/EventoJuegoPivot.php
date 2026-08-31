<?php

namespace App\Models;

use App\Models\Concerns\RecordsTombstone;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class EventoJuegoPivot extends Model
{
    use RecordsTombstone;

    protected $table = 'evento_juegos';

    protected $fillable = [
        'evento_id',
        'juego_id',
    ];

    protected $casts = [
        'evento_id' => 'integer',
        'juego_id' => 'integer',
    ];

    public function evento(): BelongsTo
    {
        return $this->belongsTo(Evento::class, 'evento_id');
    }

    public function juego(): BelongsTo
    {
        return $this->belongsTo(Juego::class, 'juego_id');
    }
}
