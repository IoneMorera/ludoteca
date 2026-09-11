<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class MobileErrorLog extends Model
{
    protected $fillable = [
        'user_id',
        'user_name',
        'app_version',
        'device_model',
        'os_version',
        'connection_type',
        'free_memory',
        'level',
        'context',
        'message',
        'stack_trace',
        'extra',
        'reported_at',
    ];

    protected $casts = [
        'extra' => 'array',
        'reported_at' => 'datetime',
    ];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
