<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('prestamos', function (Blueprint $table) {
            $table->dropForeign(['socio_id']);
            $table->dropColumn('socio_id');
            $table->string('persona')->after('juego_id');
        });

        Schema::dropIfExists('socios');
    }

    public function down(): void
    {
        Schema::create('socios', function (Blueprint $table) {
            $table->id();
            $table->string('nombre');
            $table->string('apellidos');
            $table->string('email')->nullable()->unique();
            $table->string('telefono', 20)->nullable();
            $table->date('fecha_nacimiento')->nullable();
            $table->string('direccion', 500)->nullable();
            $table->string('numero_socio')->unique();
            $table->boolean('activo')->default(true);
            $table->timestamps();
        });

        Schema::table('prestamos', function (Blueprint $table) {
            $table->dropColumn('persona');
            $table->foreignId('socio_id')->after('juego_id')->constrained('socios')->onDelete('restrict');
        });
    }
};
