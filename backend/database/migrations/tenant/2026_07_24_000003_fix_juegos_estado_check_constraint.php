<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * La columna `estado` se creó como enum ['disponible','prestado','reparacion','baja'],
     * lo que en PostgreSQL generó la restricción CHECK `juegos_estado_check`.
     * La migración 2026_05_28 cambió el tipo a VARCHAR pero nunca eliminó esa
     * restricción, por lo que seguía bloqueando los valores actuales
     * ('en_venta' y 'vendido'). Aquí la sustituimos por la correcta.
     */
    public function up(): void
    {
        DB::statement('ALTER TABLE juegos DROP CONSTRAINT IF EXISTS juegos_estado_check');

        // Normaliza cualquier valor legacy fuera del conjunto vigente.
        DB::statement("UPDATE juegos SET estado = 'disponible' WHERE estado IS NULL OR estado NOT IN ('disponible', 'en_venta', 'vendido')");

        DB::statement("ALTER TABLE juegos ADD CONSTRAINT juegos_estado_check CHECK (estado IN ('disponible', 'en_venta', 'vendido'))");
    }

    public function down(): void
    {
        DB::statement('ALTER TABLE juegos DROP CONSTRAINT IF EXISTS juegos_estado_check');
        DB::statement("ALTER TABLE juegos ADD CONSTRAINT juegos_estado_check CHECK (estado IN ('disponible', 'prestado', 'reparacion', 'baja'))");
    }
};
