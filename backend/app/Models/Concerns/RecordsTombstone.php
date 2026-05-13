<?php

namespace App\Models\Concerns;

use App\Models\Tombstone;

trait RecordsTombstone
{
    protected static function bootRecordsTombstone(): void
    {
        static::deleted(function ($model) {
            $tableName = $model->getTable();
            $recordId = $model->getKey();
            if ($recordId !== null) {
                Tombstone::record($tableName, (int) $recordId);
            }
        });
    }
}
