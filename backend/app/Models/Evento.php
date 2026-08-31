<?php

namespace App\Models;

use App\Models\Concerns\RecordsTombstone;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Evento extends Model
{
    use RecordsTombstone;

    protected $table = 'eventos';

    protected $fillable = [
        'nombre',
        'fecha_inicio',
        'fecha_fin',
        'localizacion',
        'estado',
    ];

    protected $casts = [
        'fecha_inicio' => 'datetime',
        'fecha_fin' => 'datetime',
    ];

    public function juegos(): HasMany
    {
        return $this->hasMany(EventoJuegoPivot::class, 'evento_id');
    }
}
