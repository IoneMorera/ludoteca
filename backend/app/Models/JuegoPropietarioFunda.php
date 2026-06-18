<?php

namespace App\Models;

use App\Models\Concerns\RecordsTombstone;
use Illuminate\Database\Eloquent\Model;

class JuegoPropietarioFunda extends Model
{
    use RecordsTombstone;

    protected $table = 'juego_propietario_fundas';

    protected $fillable = [
        'juego_propietario_id',
        'tipo_funda_id',
        'cantidad_cartas',
        'enfundadas',
    ];

    protected $casts = [
        'juego_propietario_id' => 'integer',
        'tipo_funda_id' => 'integer',
        'cantidad_cartas' => 'integer',
        'enfundadas' => 'boolean',
    ];

    public function juegoPropietario()
    {
        return $this->belongsTo(JuegoPropietarioPivot::class, 'juego_propietario_id');
    }

    public function tipoFunda()
    {
        return $this->belongsTo(TipoFunda::class);
    }
}
