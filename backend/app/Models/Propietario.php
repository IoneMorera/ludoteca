<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Propietario extends Model
{
    use HasFactory;

    protected $table = 'propietarios';

    protected $fillable = [
        'nombre',
    ];

    public function juegos()
    {
        return $this->belongsToMany(Juego::class, 'juego_propietario')
            ->withTimestamps();
    }
}
