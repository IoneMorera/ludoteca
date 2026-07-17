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
            $table->boolean('sin_abrir')->default(false)->after('tradumaquetado_parcial_notas');
            $table->boolean('print_and_play')->default(false)->after('sin_abrir');
        });

        // Backfill: copia principal hereda los indicadores del juego cuando hay varias copias.
        DB::statement("
            UPDATE juego_propietario jp
            SET sin_abrir = j.sin_abrir,
                print_and_play = j.print_and_play
            FROM juegos j
            WHERE jp.juego_id = j.id
              AND j.varias_copias = true
              AND jp.es_principal = true
        ");
    }

    public function down(): void
    {
        Schema::table('juego_propietario', function (Blueprint $table) {
            $table->dropColumn(['sin_abrir', 'print_and_play']);
        });
    }
};
