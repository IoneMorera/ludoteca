<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('juegos', function (Blueprint $table) {
            $table->foreignId('ubicacion_id')
                ->nullable()
                ->after('categoria_id')
                ->constrained('ubicaciones')
                ->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('juegos', function (Blueprint $table) {
            $table->dropConstrainedForeignId('ubicacion_id');
        });
    }
};

