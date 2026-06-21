<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('juego_propietario', function (Blueprint $table) {
            $table->date('fecha_compra')->nullable()->after('estado');
        });

        // Backfill: copy game-level purchase date to principal copy rows.
        DB::statement("
            UPDATE juego_propietario jp
            SET fecha_compra = j.fecha_compra
            FROM juegos j
            WHERE jp.juego_id = j.id
              AND j.varias_copias = true
              AND j.fecha_compra IS NOT NULL
              AND jp.es_principal = true
              AND jp.fecha_compra IS NULL
        ");
    }

    public function down(): void
    {
        Schema::table('juego_propietario', function (Blueprint $table) {
            $table->dropColumn('fecha_compra');
        });
    }
};
