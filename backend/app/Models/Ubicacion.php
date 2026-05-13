<?php

namespace App\Models;

use App\Models\Concerns\RecordsTombstone;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Ubicacion extends Model
{
    use HasFactory, RecordsTombstone;

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

