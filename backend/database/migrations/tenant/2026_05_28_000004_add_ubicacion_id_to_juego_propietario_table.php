<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('juego_propietario', function (Blueprint $table) {
            $table->foreignId('ubicacion_id')->nullable()->constrained('ubicaciones')->nullOnDelete()->after('propietario_id');
        });
    }

    public function down(): void
    {
        Schema::table('juego_propietario', function (Blueprint $table) {
            $table->dropConstrainedForeignId('ubicacion_id');
        });
    }
};
