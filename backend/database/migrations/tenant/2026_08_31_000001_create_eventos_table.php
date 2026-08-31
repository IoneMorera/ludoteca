<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('eventos', function (Blueprint $table) {
            $table->id();
            $table->string('nombre');
            $table->dateTime('fecha_inicio');
            $table->dateTime('fecha_fin');
            $table->string('localizacion');
            $table->string('estado')->default('abierto');
            $table->timestamps();
        });

        Schema::create('evento_juegos', function (Blueprint $table) {
            $table->id();
            $table->foreignId('evento_id')->constrained('eventos')->cascadeOnDelete();
            $table->foreignId('juego_id')->constrained('juegos')->cascadeOnDelete();
            $table->timestamps();
            $table->unique(['evento_id', 'juego_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('evento_juegos');
        Schema::dropIfExists('eventos');
    }
};
