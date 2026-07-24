<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->boolean('ocultar_por_estrenar')->default(false)->after('no_enfundo');
            $table->boolean('ocultar_faltan_traduccion')->default(false)->after('ocultar_por_estrenar');
            $table->boolean('ocultar_expansion_otro_idioma')->default(false)->after('ocultar_faltan_traduccion');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn([
                'ocultar_por_estrenar',
                'ocultar_faltan_traduccion',
                'ocultar_expansion_otro_idioma',
            ]);
        });
    }
};
