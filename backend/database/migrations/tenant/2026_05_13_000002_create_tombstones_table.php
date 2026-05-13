<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('tombstones', function (Blueprint $table) {
            $table->id();
            $table->string('table_name', 64);
            $table->unsignedBigInteger('record_id');
            $table->timestamp('deleted_at')->useCurrent();

            $table->index(['table_name', 'deleted_at']);
            $table->unique(['table_name', 'record_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('tombstones');
    }
};
