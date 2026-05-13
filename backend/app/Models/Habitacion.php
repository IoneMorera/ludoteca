<?php

namespace App\Models;

use App\Models\Concerns\RecordsTombstone;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Habitacion extends Model
{
    use HasFactory, RecordsTombstone;

    protected $table = 'habitaciones';

    protected $fillable = [
        'nombre',
    ];

    public function muebles()
    {
        return $this->hasMany(Mueble::class);
    }
}

