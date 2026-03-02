<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Mueble extends Model
{
    use HasFactory;

    protected $table = 'muebles';

    protected $fillable = [
        'habitacion_id',
        'nombre',
    ];

    public function habitacion()
    {
        return $this->belongsTo(Habitacion::class);
    }

    public function ubicaciones()
    {
        return $this->hasMany(Ubicacion::class);
    }
}

