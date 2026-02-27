<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('prestamos', function (Blueprint $table) {
            $table->id();
            $table->foreignId('juego_id')->constrained('juegos')->onDelete('restrict');
            $table->foreignId('socio_id')->constrained('socios')->onDelete('restrict');
            $table->date('fecha_prestamo');
            $table->date('fecha_devolucion_prevista');
            $table->date('fecha_devolucion_real')->nullable();
            $table->text('observaciones')->nullable();
            $table->enum('estado', ['activo', 'devuelto', 'retrasado'])->default('activo');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('prestamos');
    }
};
