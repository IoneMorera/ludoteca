<?php

namespace App\Models;

use App\Models\Concerns\RecordsTombstone;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class TipoFunda extends Model
{
    use HasFactory, RecordsTombstone;

    protected $table = 'tipos_funda';

    protected $fillable = [
        'nombre',
        'ancho_mm',
        'alto_mm',
        'descripcion',
    ];

    protected $casts = [
        'ancho_mm' => 'integer',
        'alto_mm' => 'integer',
    ];

    public function juegos()
    {
        return $this->belongsToMany(Juego::class, 'juego_fundas')
            ->withPivot(['cantidad_cartas', 'enfundadas'])
            ->withTimestamps();
    }
}
