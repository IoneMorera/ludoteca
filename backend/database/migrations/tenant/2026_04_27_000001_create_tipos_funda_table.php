<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('tipos_funda', function (Blueprint $table) {
            $table->id();
            $table->string('nombre');
            $table->unsignedSmallInteger('ancho_mm');
            $table->unsignedSmallInteger('alto_mm');
            $table->text('descripcion')->nullable();
            $table->timestamps();

            $table->unique(['ancho_mm', 'alto_mm']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('tipos_funda');
    }
};
