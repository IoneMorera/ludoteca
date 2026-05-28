<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('juegos', function (Blueprint $table) {
            $table->boolean('es_expansion')->default(false)->after('no_enfundar');
            $table->jsonb('idiomas')->nullable()->after('es_expansion');
            $table->string('idioma_otro')->nullable()->after('idiomas');
            $table->boolean('independiente_idioma')->default(false)->after('idioma_otro');
            $table->boolean('tradumaquetado')->default(false)->after('independiente_idioma');
            $table->boolean('tradumaquetado_parcial')->default(false)->after('tradumaquetado');
            $table->text('tradumaquetado_parcial_notas')->nullable()->after('tradumaquetado_parcial');
            $table->boolean('varias_copias')->default(false)->after('tradumaquetado_parcial_notas');
        });

        // Backfill es_expansion from juego_base_id
        \Illuminate\Support\Facades\DB::statement(
            "UPDATE juegos SET es_expansion = true WHERE juego_base_id IS NOT NULL"
        );
    }

    public function down(): void
    {
        Schema::table('juegos', function (Blueprint $table) {
            $table->dropColumn([
                'es_expansion',
                'idiomas',
                'idioma_otro',
                'independiente_idioma',
                'tradumaquetado',
                'tradumaquetado_parcial',
                'tradumaquetado_parcial_notas',
                'varias_copias',
            ]);
        });
    }
};
