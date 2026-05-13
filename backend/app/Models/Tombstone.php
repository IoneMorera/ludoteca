<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Tombstone extends Model
{
    public $timestamps = false;

    protected $fillable = [
        'table_name',
        'record_id',
        'deleted_at',
    ];

    protected $casts = [
        'record_id' => 'integer',
        'deleted_at' => 'datetime',
    ];

    public static function record(string $tableName, int $recordId): void
    {
        static::updateOrCreate(
            ['table_name' => $tableName, 'record_id' => $recordId],
            ['deleted_at' => now()]
        );
    }
}
