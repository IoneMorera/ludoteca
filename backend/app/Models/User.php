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
        'bgg_session',
        'bgg_connected_at',
        'no_enfundo',
        'ocultar_por_estrenar',
        'ocultar_faltan_traduccion',
        'ocultar_expansion_otro_idioma',
        'ocultar_por_colocar',
    ];

    protected $hidden = [
        'password',
        'remember_token',
        'bgg_session',
    ];

    protected $casts = [
        'email_verified_at' => 'datetime',
        'password' => 'hashed',
        'bgg_session' => 'encrypted',
        'bgg_connected_at' => 'datetime',
        'no_enfundo' => 'boolean',
        'ocultar_por_estrenar' => 'boolean',
        'ocultar_faltan_traduccion' => 'boolean',
        'ocultar_expansion_otro_idioma' => 'boolean',
        'ocultar_por_colocar' => 'boolean',
    ];

    public function tenant()
    {
        return $this->belongsTo(Tenant::class);
    }

    public function isBggConnected(): bool
    {
        return filled($this->bgg_username) && filled($this->bgg_session);
    }

    public function toApiArray(): array
    {
        return array_merge(
            $this->only(
                'id',
                'name',
                'email',
                'bgg_username',
                'no_enfundo',
                'ocultar_por_estrenar',
                'ocultar_faltan_traduccion',
                'ocultar_expansion_otro_idioma',
                'ocultar_por_colocar',
            ),
            [
                'bgg_connected' => $this->isBggConnected(),
            ],
        );
    }
}
