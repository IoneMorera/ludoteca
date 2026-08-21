<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('bgg_expansiones', function (Blueprint $table) {
            $table->id();
            $table->unsignedInteger('base_bgg_id');
            $table->unsignedInteger('expansion_bgg_id');
            $table->string('nombre');
            $table->unsignedSmallInteger('anio')->nullable();
            $table->string('imagen')->nullable();
            $table->unsignedTinyInteger('min_jugadores')->nullable();
            $table->unsignedTinyInteger('max_jugadores')->nullable();
            $table->boolean('ignorada')->default(false);
            $table->timestamps();

            $table->unique(['base_bgg_id', 'expansion_bgg_id']);
            $table->index('base_bgg_id');
            $table->index('expansion_bgg_id');
            $table->index('updated_at');
        });

        Schema::create('bgg_expansion_checks', function (Blueprint $table) {
            $table->unsignedInteger('base_bgg_id')->primary();
            $table->timestamp('checked_at')->nullable();
            $table->unsignedInteger('links_count')->default(0);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('bgg_expansion_checks');
        Schema::dropIfExists('bgg_expansiones');
    }
};
