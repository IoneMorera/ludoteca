<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('juegos', function (Blueprint $table) {
            $table->boolean('no_enfundar')->default(false)->after('estado');
            $table->index('updated_at', 'juegos_updated_at_index');
        });
    }

    public function down(): void
    {
        Schema::table('juegos', function (Blueprint $table) {
            $table->dropIndex('juegos_updated_at_index');
            $table->dropColumn('no_enfundar');
        });
    }
};
