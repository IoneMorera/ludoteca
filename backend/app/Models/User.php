<?php

namespace App\Models;

use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable
{
    use HasApiTokens, Notifiable;

    protected $connection = 'central';

    protected $fillable = [
        'name',
        'email',
        'password',
        'tenant_id',
        'bgg_username',
        'no_enfundo',
        'ocultar_por_estrenar',
        'ocultar_faltan_traduccion',
        'ocultar_expansion_otro_idioma',
    ];

    protected $hidden = [
        'password',
        'remember_token',
    ];

    protected $casts = [
        'email_verified_at' => 'datetime',
        'password' => 'hashed',
        'no_enfundo' => 'boolean',
        'ocultar_por_estrenar' => 'boolean',
        'ocultar_faltan_traduccion' => 'boolean',
        'ocultar_expansion_otro_idioma' => 'boolean',
    ];

    public function tenant()
    {
        return $this->belongsTo(Tenant::class);
    }
}
