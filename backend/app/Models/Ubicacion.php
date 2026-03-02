<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Ubicacion extends Model
{
    use HasFactory;

    protected $table = 'ubicaciones';

    protected $fillable = [
        'mueble_id',
        'nombre',
    ];

    public function mueble()
    {
        return $this->belongsTo(Mueble::class);
    }
}

