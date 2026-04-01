<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('juegos', function (Blueprint $table) {
            $table->id();
            $table->string('nombre');
            $table->text('descripcion')->nullable();
            $table->unsignedTinyInteger('edad_minima')->nullable();
            $table->unsignedTinyInteger('edad_maxima')->nullable();
            $table->unsignedTinyInteger('num_jugadores_min')->nullable();
            $table->unsignedTinyInteger('num_jugadores_max')->nullable();
            $table->foreignId('categoria_id')->constrained('categorias')->onDelete('restrict');
            $table->enum('estado', ['disponible', 'prestado', 'reparacion', 'baja'])->default('disponible');
            $table->string('imagen')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('juegos');
    }
};
