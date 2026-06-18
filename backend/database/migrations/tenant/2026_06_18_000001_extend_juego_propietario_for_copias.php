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
            $table->boolean('es_principal')->default(false)->after('ubicacion_id');
            $table->string('estado', 20)->nullable()->after('es_principal');
            $table->boolean('no_enfundar')->default(false)->after('estado');
            $table->jsonb('idiomas')->nullable()->after('no_enfundar');
            $table->string('idioma_otro')->nullable()->after('idiomas');
            $table->boolean('independiente_idioma')->default(false)->after('idioma_otro');
            $table->boolean('tradumaquetado')->default(false)->after('independiente_idioma');
            $table->boolean('tradumaquetado_parcial')->default(false)->after('tradumaquetado');
            $table->text('tradumaquetado_parcial_notas')->nullable()->after('tradumaquetado_parcial');
        });

        Schema::create('juego_propietario_fundas', function (Blueprint $table) {
            $table->id();
            $table->foreignId('juego_propietario_id')
                ->constrained('juego_propietario')
                ->cascadeOnDelete();
            $table->foreignId('tipo_funda_id')->constrained('tipos_funda')->cascadeOnDelete();
            $table->unsignedSmallInteger('cantidad_cartas');
            $table->boolean('enfundadas')->default(false);
            $table->timestamps();

            $table->unique(['juego_propietario_id', 'tipo_funda_id']);
        });

        DB::statement('GRANT SELECT, INSERT, UPDATE, DELETE ON public.juego_propietario_fundas TO anon, authenticated, service_role');
        DB::statement('GRANT USAGE, SELECT ON SEQUENCE juego_propietario_fundas_id_seq TO anon, authenticated, service_role');

        // Backfill: mark principal copy where owner location matches game location.
        DB::statement("
            UPDATE juego_propietario jp
            SET es_principal = true
            FROM juegos j
            WHERE jp.juego_id = j.id
              AND j.varias_copias = true
              AND j.ubicacion_id IS NOT NULL
              AND jp.ubicacion_id = j.ubicacion_id
        ");
    }

    public function down(): void
    {
        Schema::dropIfExists('juego_propietario_fundas');

        Schema::table('juego_propietario', function (Blueprint $table) {
            $table->dropColumn([
                'es_principal',
                'estado',
                'no_enfundar',
                'idiomas',
                'idioma_otro',
                'independiente_idioma',
                'tradumaquetado',
                'tradumaquetado_parcial',
                'tradumaquetado_parcial_notas',
            ]);
        });
    }
};
