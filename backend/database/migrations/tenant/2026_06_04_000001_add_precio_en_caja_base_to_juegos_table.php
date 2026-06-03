<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('juegos', function (Blueprint $table) {
            $table->decimal('precio', 8, 2)->nullable()->after('varias_copias');
            $table->boolean('en_caja_base')->default(false)->after('precio');
        });
    }

    public function down(): void
    {
        Schema::table('juegos', function (Blueprint $table) {
            $table->dropColumn(['precio', 'en_caja_base']);
        });
    }
};
