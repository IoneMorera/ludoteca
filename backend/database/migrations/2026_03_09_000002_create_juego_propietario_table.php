<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('juego_propietario', function (Blueprint $table) {
            $table->id();
            $table->foreignId('juego_id')->constrained('juegos')->cascadeOnDelete();
            $table->foreignId('propietario_id')->constrained('propietarios')->cascadeOnDelete();
            $table->timestamps();

            $table->unique(['juego_id', 'propietario_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('juego_propietario');
    }
};
