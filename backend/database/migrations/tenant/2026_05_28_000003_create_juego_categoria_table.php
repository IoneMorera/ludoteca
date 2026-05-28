<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('juego_categoria', function (Blueprint $table) {
            $table->id();
            $table->foreignId('juego_id')->constrained('juegos')->cascadeOnDelete();
            $table->foreignId('categoria_id')->constrained('categorias')->cascadeOnDelete();
            $table->timestamps();
            $table->unique(['juego_id', 'categoria_id']);
        });

        // Supabase breaking change: explicit GRANTs for new tables
        DB::statement('GRANT SELECT, INSERT, UPDATE, DELETE ON public.juego_categoria TO anon, authenticated, service_role');
        DB::statement('GRANT USAGE, SELECT ON SEQUENCE juego_categoria_id_seq TO anon, authenticated, service_role');

        // Migrate existing categoria_id data to the pivot table
        DB::statement("
            INSERT INTO juego_categoria (juego_id, categoria_id, created_at, updated_at)
            SELECT id, categoria_id, NOW(), NOW()
            FROM juegos
            WHERE categoria_id IS NOT NULL
        ");

        // Make categoria_id nullable (deprecated, will be removed later)
        Schema::table('juegos', function (Blueprint $table) {
            $table->foreignId('categoria_id')->nullable()->change();
        });
    }

    public function down(): void
    {
        // Restore categoria_id from pivot
        DB::statement("
            UPDATE juegos SET categoria_id = (
                SELECT jc.categoria_id FROM juego_categoria jc
                WHERE jc.juego_id = juegos.id
                LIMIT 1
            )
        ");

        Schema::dropIfExists('juego_categoria');
    }
};
