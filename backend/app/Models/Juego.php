<?php

namespace App\Models;

use App\Models\Concerns\RecordsTombstone;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Juego extends Model
{
    use HasFactory, RecordsTombstone;

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
        'juego_base_id',
        'no_enfundar',
        'es_expansion',
        'autojugable',
        'idiomas',
        'idioma_otro',
        'independiente_idioma',
        'tradumaquetado',
        'tradumaquetado_parcial',
        'tradumaquetado_parcial_notas',
        'varias_copias',
        'precio',
        'en_caja_base',
        'sin_abrir',
        'print_and_play',
    ];

    protected $casts = [
        'edad_minima' => 'integer',
        'edad_maxima' => 'integer',
        'num_jugadores_min' => 'integer',
        'num_jugadores_max' => 'integer',
        'fecha_compra' => 'date:Y-m-d',
        'bgg_id' => 'integer',
        'juego_base_id' => 'integer',
        'no_enfundar' => 'boolean',
        'es_expansion' => 'boolean',
        'autojugable' => 'boolean',
        'idiomas' => 'array',
        'independiente_idioma' => 'boolean',
        'tradumaquetado' => 'boolean',
        'tradumaquetado_parcial' => 'boolean',
        'varias_copias' => 'boolean',
        'precio' => 'decimal:2',
        'en_caja_base' => 'boolean',
        'sin_abrir' => 'boolean',
        'print_and_play' => 'boolean',
    ];

    public function categoria()
    {
        return $this->belongsTo(Categoria::class);
    }

    public function categorias()
    {
        return $this->belongsToMany(Categoria::class, 'juego_categoria')
            ->withTimestamps();
    }

    public function ubicacion()
    {
        return $this->belongsTo(Ubicacion::class);
    }

    public function prestamos()
    {
        return $this->hasMany(Prestamo::class);
    }

    public function propietarios()
    {
        return $this->belongsToMany(Propietario::class, 'juego_propietario')
            ->withPivot('ubicacion_id')
            ->withTimestamps();
    }

    public function fundas()
    {
        return $this->hasMany(JuegoFunda::class);
    }

    public function juegoBase()
    {
        return $this->belongsTo(Juego::class, 'juego_base_id');
    }

    public function expansiones()
    {
        return $this->hasMany(Juego::class, 'juego_base_id');
    }
}
