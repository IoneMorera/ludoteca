<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Prestamo extends Model
{
    use HasFactory;

    protected $table = 'prestamos';

    protected $fillable = [
        'juego_id',
        'persona',
        'fecha_prestamo',
        'fecha_devolucion_prevista',
        'fecha_devolucion_real',
        'observaciones',
        'estado',
    ];

    protected $casts = [
        'fecha_prestamo' => 'date',
        'fecha_devolucion_prevista' => 'date',
        'fecha_devolucion_real' => 'date',
    ];

    public function juego()
    {
        return $this->belongsTo(Juego::class);
    }
}
