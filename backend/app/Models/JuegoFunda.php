<?php

namespace App\Models;

use App\Models\Concerns\RecordsTombstone;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class JuegoFunda extends Model
{
    use HasFactory, RecordsTombstone;

    protected $table = 'juego_fundas';

    protected $fillable = [
        'juego_id',
        'tipo_funda_id',
        'cantidad_cartas',
        'enfundadas',
    ];

    protected $casts = [
        'juego_id' => 'integer',
        'tipo_funda_id' => 'integer',
        'cantidad_cartas' => 'integer',
        'enfundadas' => 'boolean',
    ];

    public function juego()
    {
        return $this->belongsTo(Juego::class);
    }

    public function tipoFunda()
    {
        return $this->belongsTo(TipoFunda::class);
    }
}
