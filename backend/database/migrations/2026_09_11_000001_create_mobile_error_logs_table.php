<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('mobile_error_logs', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('user_name')->nullable();
            $table->string('app_version', 20)->nullable();
            $table->string('device_model')->nullable();
            $table->string('os_version', 80)->nullable();
            $table->string('connection_type', 40)->nullable();
            $table->string('free_memory', 40)->nullable();
            $table->string('level', 20)->default('error');
            $table->string('context');
            $table->text('message');
            $table->text('stack_trace')->nullable();
            $table->json('extra')->nullable();
            $table->timestamp('reported_at');
            $table->timestamps();

            $table->index(['user_id', 'reported_at']);
            $table->index('level');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('mobile_error_logs');
    }
};
