<?php

namespace App\Models;

use App\Models\Concerns\RecordsTombstone;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Propietario extends Model
{
    use HasFactory, RecordsTombstone;

    protected $table = 'propietarios';

    protected $fillable = [
        'nombre',
        'bgg_username',
        'es_principal',
    ];

    protected $casts = [
        'es_principal' => 'boolean',
    ];

    public function juegos()
    {
        return $this->belongsToMany(Juego::class, 'juego_propietario')
            ->withTimestamps();
    }
}
