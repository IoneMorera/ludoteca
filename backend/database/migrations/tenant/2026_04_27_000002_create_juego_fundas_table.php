<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('juego_fundas', function (Blueprint $table) {
            $table->id();
            $table->foreignId('juego_id')->constrained('juegos')->cascadeOnDelete();
            $table->foreignId('tipo_funda_id')->constrained('tipos_funda')->restrictOnDelete();
            $table->unsignedSmallInteger('cantidad_cartas');
            $table->boolean('enfundadas')->default(false);
            $table->timestamps();

            $table->unique(['juego_id', 'tipo_funda_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('juego_fundas');
    }
};
