<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        // Migrate existing data to new values
        DB::statement("UPDATE juegos SET estado = 'disponible' WHERE estado NOT IN ('disponible', 'en_venta', 'vendido')");

        // Change column type from enum to varchar for flexibility
        DB::statement("ALTER TABLE juegos ALTER COLUMN estado TYPE VARCHAR(20)");
        DB::statement("ALTER TABLE juegos ALTER COLUMN estado SET DEFAULT 'disponible'");

        // Drop the old enum type if it exists
        DB::statement("DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'juegos_estado') THEN DROP TYPE juegos_estado; END IF; END $$;");
    }

    public function down(): void
    {
        DB::statement("UPDATE juegos SET estado = 'disponible' WHERE estado NOT IN ('disponible', 'prestado', 'reparacion', 'baja')");
        DB::statement("ALTER TABLE juegos ALTER COLUMN estado TYPE VARCHAR(20)");
    }
};
