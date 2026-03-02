<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Juego extends Model
{
    use HasFactory;

    protected $table = 'juegos';

    protected $fillable = [
        'nombre',
        'descripcion',
        'edad_minima',
        'edad_maxima',
        'num_jugadores_min',
        'num_jugadores_max',
        'categoria_id',
        'ubicacion_id',
        'estado',
        'fecha_compra',
        'imagen',
        'bgg_id',
    ];

    protected $casts = [
        'edad_minima' => 'integer',
        'edad_maxima' => 'integer',
        'num_jugadores_min' => 'integer',
        'num_jugadores_max' => 'integer',
        'fecha_compra' => 'date:Y-m-d',
        'bgg_id' => 'integer',
    ];

    public function categoria()
    {
        return $this->belongsTo(Categoria::class);
    }

    public function ubicacion()
    {
        return $this->belongsTo(Ubicacion::class);
    }

    public function prestamos()
    {
        return $this->hasMany(Prestamo::class);
    }
}
