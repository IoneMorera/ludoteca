<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('juegos', function (Blueprint $table) {
            $table->foreignId('juego_base_id')
                ->nullable()
                ->after('bgg_id')
                ->constrained('juegos')
                ->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('juegos', function (Blueprint $table) {
            $table->dropForeign(['juego_base_id']);
            $table->dropColumn('juego_base_id');
        });
    }
};
